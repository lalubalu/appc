import assert from "node:assert/strict";
import { parseGeometry, normalizeGeometry, containsPoint, intersectsBoundary, bounds } from "../lib/parks/geometry.js";
import { normalizeFeature, sourceStatus, joinParkGeometry, parkIdsAt, officialURL } from "../lib/parks/normalize.js";
import { fetchSource, verifyPermission, SOURCE_SPECS, TERMS_REVIEW_EXPIRES_MS, requestJSON } from "../lib/parks/sources.js";
let passed = 0;
function check(name, work) { work(); passed++; console.log(`PASS ${name}`); }
async function test(name, work) { await work(); passed++; console.log(`PASS ${name}`); }
const ring = [[0,0],[10,0],[10,10],[0,10],[0,0]], hole = [[2,2],[4,2],[4,4],[2,4],[2,2]];
const park = parseGeometry({ type: "Polygon", coordinates: [ring, hole] });
check("polygon interior and boundary join", () => { assert.ok(containsPoint(park, [1,1])); assert.ok(containsPoint(park, [0,5])); });
check("polygon hole interior excludes a place", () => assert.equal(containsPoint(park, [3,3]), false));
check("hole boundary is part of park boundary", () => assert.ok(containsPoint(park, [2,3])));
check("point outside overlapping bounding boxes does not join", () => { const triangle = parseGeometry({type:"Polygon", coordinates:[[[0,0],[10,0],[0,10],[0,0]]]}); assert.equal(containsPoint(triangle,[9,9]),false); });
check("multi-polygon islands join independently", () => { const g = parseGeometry({type:"MultiPolygon", coordinates:[[ring],[[[20,20],[21,20],[21,21],[20,21],[20,20]]]]}); assert.ok(containsPoint(g,[20.5,20.5])); assert.equal(containsPoint(g,[15,15]),false); });
check("crossing trail joins with both endpoints outside", () => assert.ok(intersectsBoundary(parseGeometry({type:"LineString",coordinates:[[-1,5],[11,5]]}),park)));
check("line entirely in a hole does not join", () => assert.equal(intersectsBoundary(parseGeometry({type:"LineString",coordinates:[[2.5,3],[3.5,3]]}),park),false));
check("polygon containing the park joins", () => assert.ok(intersectsBoundary(parseGeometry({type:"Polygon",coordinates:[[[-1,-1],[11,-1],[11,11],[-1,11],[-1,-1]]]}),park)));
check("collinear boundary segment joins", () => assert.ok(intersectsBoundary(parseGeometry({type:"LineString",coordinates:[[-1,0],[2,0]]}),park)));
check("multi-line only needs one actual intersecting segment", () => assert.ok(intersectsBoundary(parseGeometry({type:"MultiLineString",coordinates:[[[20,20],[21,21]],[[-1,5],[11,5]]]}),park)));
check("geometry bounds use longitude then latitude", () => assert.deepEqual(bounds(parseGeometry({type:"Point",coordinates:[-121,37]})),{west:-121,east:-121,south:37,north:37}));
for (const [name,value] of Object.entries({missing:null,projected:{type:"Point",coordinates:[1000000,2000000]},nonfinite:{type:"Point",coordinates:[NaN,1]},strings:{type:"Point",coordinates:["1",2]},unclosed:{type:"Polygon",coordinates:[[[0,0],[1,0],[1,1],[0,1]]]},empty:{type:"MultiPolygon",coordinates:[]},unsupported:{type:"GeometryCollection",geometries:[]}})) check(`reject ${name} geometry`,()=>assert.throws(()=>parseGeometry(value)));
check("oversized geometry rejected before storage",()=>assert.throws(()=>parseGeometry({type:"LineString",coordinates:Array.from({length:250001},()=>[1,1])}),/vertex limit/));
check("ArcGIS empty component omitted with a recorded note and valid part intact",()=> {const n=normalizeGeometry({type:"MultiPolygon",coordinates:[[[[1,1],[2,2],[1,1]]],[ring]]});assert.deepEqual(n.geometry.coordinates,[[ring]]);assert.equal(n.notes.length,1);});
check("all-degenerate multipolygon cannot become a usable boundary",()=>assert.throws(()=>normalizeGeometry({type:"MultiPolygon",coordinates:[[[[1,1],[2,2],[1,1]]]]}),/Empty/));
check("degenerate-component normalization never hides invalid coordinates",()=>assert.throws(()=>normalizeGeometry({type:"MultiPolygon",coordinates:[[[[NaN,1],[2,2],[NaN,1]]],[ring]]}),/Invalid/));
const now = Date.UTC(2026,9,4), city = SOURCE_SPECS[0], county = SOURCE_SPECS.find(s=>s.id==="county-trails");
const permission = {success:true,result:{license_id:"cc-by",license_url:city.credit.licenseURL,resources:[{url:city.layerURL}]}};
check("city CC BY and source linkage required",()=> { verifyPermission(city,permission,now); assert.throws(()=>verifyPermission(city,{...permission,result:{...permission.result,license_id:"proprietary"}},now),/license changed/); });
check("expired policy review stops ingest",()=>assert.throws(()=>verifyPermission(city,permission,TERMS_REVIEW_EXPIRES_MS),/expired/));
const cm = {id:county.countyItem,owner:"sccprk",access:"public",licenseInfo:null,url:county.layerURL.replace(/\/\d+$/,"")};
check("county permission uses recorded policy and County-owned public item",()=>verifyPermission(county,cm,now));
for (const patch of [{owner:"third-party"},{access:"private"},{licenseInfo:"all rights reserved"},{url:"https://attacker.test/feed"}]) check(`county rejects ${Object.keys(patch)[0]} change`,()=>assert.throws(()=>verifyPermission(county,{...cm,...patch},now),/permission/));
await test("HTTP and arbitrary hosts rejected before fetch",async()=> { await assert.rejects(requestJSON("http://geo.sanjoseca.gov/feed"),/Unapproved/); await assert.rejects(requestJSON("https://attacker.test/feed"),/Unapproved/); });
function feature(id, properties={}, geometry=park) {return {type:"Feature",properties:{OBJECTID:id,NAME:"Fixture",CURRENTSTATUS:"Open",...properties},geometry};}
function sourceRequest({count=151,change,metadata=permission}={}) {
 const requests=[];
 return {requests, request:async(url)=> {
  requests.push(url); if(url===city.metadataURL)return metadata;
  if(url===`${city.layerURL}?f=json`)return {fields:["OBJECTID",...city.fields].map(name=>({name}))};
  const u=new URL(url); if(u.searchParams.get("returnIdsOnly")) return {objectIds:Array.from({length:count},(_,i)=>i+1)};
  const ids=u.searchParams.get("objectIds").split(",").map(Number), page={type:"FeatureCollection",features:ids.map(id=>feature(id))};
  return change?change(page,u):page;
 }};
}
await test("all 151 IDs fetched as exact 100/51 pages",async()=> {const m=sourceRequest();const s=await fetchSource(city.id,m.request,now); assert.equal(s.features.length,151); assert.deepEqual(m.requests.filter(u=>u.includes("objectIds=")).map(u=>new URL(u).searchParams.get("objectIds").split(",").length),[100,51]);});
await test("permission rejection happens before requesting features",async()=> {const m=sourceRequest({metadata:{success:false}});await assert.rejects(fetchSource(city.id,m.request,now),/license changed/);assert.equal(m.requests.length,1);});
await test("empty snapshot cannot erase catalog",async()=> {const m=sourceRequest({count:0});await assert.rejects(fetchSource(city.id,m.request,now),/empty/);});
await test("truncated page refuses whole source",async()=> {const m=sourceRequest({change:p=>({...p,features:p.features.slice(0,-1)})});await assert.rejects(fetchSource(city.id,m.request,now),/Incomplete/);});
await test("duplicate ID in a complete-size page refuses source",async()=> {const m=sourceRequest({change:p=>({...p,features:p.features.map((f,i)=>i===1?p.features[0]:f)})});await assert.rejects(fetchSource(city.id,m.request,now),/duplicate/);});
await test("unexpected feature ID refuses source",async()=> {const m=sourceRequest({change:p=>({...p,features:[feature(9999),...p.features.slice(1)]})});await assert.rejects(fetchSource(city.id,m.request,now),/unexpected/);});
await test("exceeded-transfer flag is a failure even with full-size page",async()=> {const m=sourceRequest({change:p=>({...p,exceededTransferLimit:true})});await assert.rejects(fetchSource(city.id,m.request,now),/Incomplete/);});
await test("case variants of public distribution accepted, restricted data rejected",async()=> {
 const spec=SOURCE_SPECS.find(s=>s.id==="county-poi"); let distribution="public";
 const request=async url=>url===spec.metadataURL?{id:spec.countyItem,owner:"sccprk",access:"public",licenseInfo:null,url:spec.layerURL.replace(/\/\d+$/,"")}:
   url===`${spec.layerURL}?f=json`?{fields:["OBJECTID",...spec.fields].map(name=>({name}))}:new URL(url).searchParams.get("returnIdsOnly")?{objectIds:[1]}:
   {type:"FeatureCollection",features:[feature(1,{distribution},{type:"Point",coordinates:[1,1]})]};
 assert.equal((await fetchSource(spec.id,request,now)).features.length,1); distribution="Internal Only";await assert.rejects(fetchSource(spec.id,request,now),/Non-public/);
});
for (const [input,status] of [["Open","open"],["Closed","closed"],["closed/land bank","closed"],["Future Park (unsecured)","future"],["Construction","construction"],["Seasonal","seasonal"],["Permit","permit"],["unrecognised","unknown"]]) check(`status ${input} is ${status}`,()=>assert.equal(sourceStatus(input),status));
check("closed park never becomes open",()=>assert.equal(normalizeFeature("city-parks",feature(1,{CURRENTSTATUS:"Closed"})).status,"closed"));
check("null geometry counted as unjoinable",()=>assert.equal(normalizeFeature("city-parks",feature(1,{},null)),null));
check("toddler and youth age ranges come from structured types",()=> {assert.deepEqual(normalizeFeature("city-amenities",feature(1,{AMENITYTYPE:"PLAYTOT",AMENITYSTATUS:"Open"})).amenities[0].ages,[2,5]);assert.deepEqual(normalizeFeature("city-amenities",feature(1,{AMENITYTYPE:"PLAYYOUTH",AMENITYSTATUS:"Open"})).amenities[0].ages,[5,12]);});
check("all-ages and county play areas invent no numeric age range",()=> {assert.equal(normalizeFeature("city-amenities",feature(1,{AMENITYTYPE:"PLAYCOMB"})).amenities[0].ages,null); assert.equal(normalizeFeature("county-poi",feature(1,{type:"PLAY AREA"},{type:"Point",coordinates:[1,1]})).amenities[0].ages,null);});
check("water bodies, decorative fountains and splash play are not drinking water",()=> {for(const type of ["WATERB","FOUNTAIN","WATERPLY"])assert.equal(normalizeFeature("city-amenities",feature(1,{AMENITYTYPE:type})).amenities.some(a=>a.kind==="water"),false);});
check("drinking fountain and confirmed restroom attributes mapped",()=>assert.deepEqual(normalizeFeature("city-amenities",feature(1,{AMENITYTYPE:"DRINKF",RESTROOMACCESS:1})).amenities.map(a=>a.kind),["water","restrooms"]));
check("missing county water/restroom flags do not confirm amenities",()=>assert.deepEqual(normalizeFeature("county-poi",feature(1,{type:"GENERAL PARK FEATURE",drinking_water:"",restroom:""},{type:"Point",coordinates:[1,1]})).amenities,[]));
check("county typed restroom is confirmed without fabricated hours",()=> {const f=normalizeFeature("county-poi",feature(1,{type:"RESTROOM"},{type:"Point",coordinates:[1,1]}));assert.equal(f.amenities[0].kind,"restrooms");assert.equal(f.status,"unknown");assert.equal(f.hours,undefined);});
check("trail source length retained without inferred elevation or width units",()=> {const f=normalizeFeature("county-trails",feature(1,{miles:0.3,width:4,public_use:"hiking",status:"open",width_class:"narrow"},{type:"LineString",coordinates:[[1,1],[2,1]]}));assert.equal(f.trail.lengthMiles,0.3);assert.equal(f.trail.widthUnit,null);assert.equal(f.trail.widthClass,"5 ft or less");assert.equal(f.trail.elevation,null);assert.match(f.trail.notice,/Follow posted signs/);});
check("restricted trail never presented as publicly open",()=> {const f=normalizeFeature("county-trails",feature(1,{status:"open",public_use:"no public access"},{type:"LineString",coordinates:[[1,1],[2,1]]}));assert.equal(f.status,"restricted");assert.equal(f.trail.publicAccess,false);});
check("dog permissions preserve yes, no and unknown",()=> {for(const [v,out] of [["on leash","on leash"],["no access","not allowed"],[null,"unknown"]])assert.equal(normalizeFeature("county-trails",feature(1,{public_use:"hiking",dog_use:v},{type:"LineString",coordinates:[[1,1],[2,1]]})).trail.dogs,out);});
check("official links reject active schemes and unapproved sites",()=> {assert.ok(officialURL("javascript:alert(1)","city-parks").startsWith("https://www.sanjoseca.gov/"));assert.ok(officialURL("https://attacker.test/","county-trails").startsWith("https://parks.santaclaracounty.gov/"));});
check("geometry joins ignore conflicting names and preserve holes",()=> {const p=normalizeFeature("city-parks",feature(1,{NAME:"One"}));const a=normalizeFeature("county-poi",feature(2,{name:"Other"},{type:"Point",coordinates:[1,1]}));const sameName=normalizeFeature("county-poi",feature(3,{name:"One"},{type:"Point",coordinates:[3,3]}));joinParkGeometry([p,a,sameName]);assert.deepEqual(a.parkIds,[p.id]);assert.deepEqual(sameName.parkIds,[]);assert.deepEqual(parkIdsAt([p],[1,1]),[p.id]);assert.deepEqual(parkIdsAt([p],[3,3]),[]);});
console.log(`${passed} park unit checks passed`);
