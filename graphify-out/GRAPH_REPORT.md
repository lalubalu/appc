# Graph Report - .  (2026-05-18)

## Corpus Check
- Corpus is ~29,941 words - fits in a single context window. You may not need a graph.

## Summary
- 324 nodes · 714 edges · 12 communities detected
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 99 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Collection & Celebration UI|Collection & Celebration UI]]
- [[_COMMUNITY_Core Data Models|Core Data Models]]
- [[_COMMUNITY_Events API & Backend|Events API & Backend]]
- [[_COMMUNITY_App Core & Game State|App Core & Game State]]
- [[_COMMUNITY_Auth & Error Handling|Auth & Error Handling]]
- [[_COMMUNITY_API Protocols & Errors|API Protocols & Errors]]
- [[_COMMUNITY_Social & Rewards UI|Social & Rewards UI]]
- [[_COMMUNITY_Location Services|Location Services]]
- [[_COMMUNITY_Daily Gem & Typography|Daily Gem & Typography]]
- [[_COMMUNITY_Reward Confirmation|Reward Confirmation]]
- [[_COMMUNITY_Rarity Badge Sizes|Rarity Badge Sizes]]
- [[_COMMUNITY_Rarity Model (Isolated)|Rarity Model (Isolated)]]

## God Nodes (most connected - your core abstractions)
1. `GameStateManager` - 41 edges
2. `EventsAPIService` - 32 edges
3. `PlacesAPIService` - 32 edges
4. `SampleData` - 21 edges
5. `EventCategory` - 20 edges
6. `AuthService` - 19 edges
7. `PlaceCategory` - 18 edges
8. `CollectiblePlace` - 18 edges
9. `Place` - 17 edges
10. `Event` - 17 edges

## Surprising Connections (you probably didn't know these)
- `CollectionCelebrationView` --semantically_similar_to--> `Gamification Loop (Explore → Collect → Points → Rewards)`  [INFERRED] [semantically similar]
  Connectify/Connectify/Views/Collection/CollectionCelebrationView.swift → CLAUDE.md
- `Gamification Loop (Explore → Collect → Points → Rewards)` --references--> `GameStateManager`  [INFERRED]
  CLAUDE.md → Connectify/Connectify/Models/GameStateManager.swift
- `ProfileView` --implements--> `Dual Currency System (XP vs Points)`  [INFERRED]
  Connectify/Connectify/Views/Profile/ProfileView.swift → CLAUDE.md
- `Event Check-In (proximity + photo proof)` --conceptually_related_to--> `Proximity-Based Collection (500ft gate)`  [INFERRED]
  Connectify/Connectify/Views/Events/EventsView.swift → CLAUDE.md
- `Dual Currency System (XP vs Points)` --references--> `GameStateManager`  [INFERRED]
  CLAUDE.md → Connectify/Connectify/Models/GameStateManager.swift

## Hyperedges (group relationships)
- **App-Level Service Injection via SwiftUI Environment** — connectifyapp_connectifyapp, gamestatemanager_gamestatemanager, authservice_authservice, firestoreservice_firestoreservice, placesapiservice_placesapiservice, eventsapiservice_eventsapiservice, locationmanager_locationmanager, maintabview_maintabview [EXTRACTED 0.97]
- **Gamification Economy: Points Earned via Events and Places, Redeemed for Rewards** — gamestatemanager_gamestatemanager, models_event, collectionmodels_collectibleplace, collectionmodels_reward, collectionmodels_placerarity, models_eventcategory [EXTRACTED 0.95]
- **API-to-SampleData Offline Fallback Pattern** — placesapiservice_placesapiservice, eventsapiservice_eventsapiservice, sampledata_sampledata [EXTRACTED 0.92]
- **Place Collection Flow (Explore → Detail → Collect → Celebrate → Points)** — exploreview_exploreview, placedetailview_placedetailview, collectioncelebrationview_collectioncelebrationview, gamestatemanager_gamestatemanager, concept_proximity_collection [INFERRED 0.90]
- **Event Check-In Flow (EventsView → EventDetailSheet → GPS+Photo → Points)** — eventsview_eventsview, eventsview_eventdetailsheet, locationmanager_locationmanager, gamestatemanager_gamestatemanager, concept_event_checkin [EXTRACTED 0.92]
- **Rewards Redemption Flow (CollectionView/ProfileView → RewardsStore → RewardConfirmation)** — collectionview_collectionview, profileview_profileview, rewardstorev_rewardsstoreview, rewardconfirmationview_rewardconfirmationview, gamestatemanager_gamestatemanager [INFERRED 0.88]

## Communities

### Community 0 - "Collection & Celebration UI"
Cohesion: 0.07
Nodes (43): CollectionCelebrationView, Particle, CategoryCollectionCard, CollectibleDetailSheet, CollectionCard, CollectionView, Celebration Overlay Pattern, Gamification Loop (Explore → Collect → Points → Rewards) (+35 more)

### Community 1 - "Core Data Models"
Cohesion: 0.07
Nodes (33): CaseIterable, Codable, CollectiblePlace, PlaceRarity, common, legendary, rare, uncommon (+25 more)

### Community 2 - "Events API & Backend"
Cohesion: 0.08
Nodes (17): CachedEvent, EventsAPIService, CreateEventSheet, EventCard, EventsView, Event, EventCategory, cleanup (+9 more)

### Community 3 - "App Core & Game State"
Cohesion: 0.07
Nodes (10): App, Dual Currency System (XP vs Points), Event Check-In (proximity + photo proof), ConnectifyApp, EventDetailSheet, CloudGameState, FirestoreService, Limits (+2 more)

### Community 4 - "Auth & Error Handling"
Cohesion: 0.13
Nodes (14): AuthError, emptyPassword, invalidEmail, missingName, networkError, unknown, userNotFound, weakPassword (+6 more)

### Community 5 - "API Protocols & Errors"
Cohesion: 0.12
Nodes (20): Decodable, EventsAPIError, decodingError, invalidURL, notAuthenticated, rateLimited, serverError, SerpApiDate (+12 more)

### Community 6 - "Social & Rewards UI"
Cohesion: 0.16
Nodes (7): CommunityView, PostCard, RewardsStoreView, ButtonStyle, ghost, primary, secondary

### Community 7 - "Location Services"
Cohesion: 0.16
Nodes (5): CLLocationManagerDelegate, Delegate, LocationManager, NSObject, Sendable

### Community 8 - "Daily Gem & Typography"
Cohesion: 0.18
Nodes (5): DailyGemView, GemOutlineShape, GemstoneView, SparkleStarView, Shape

### Community 9 - "Reward Confirmation"
Cohesion: 0.5
Nodes (3): Equatable, Hashable, Reward

### Community 10 - "Rarity Badge Sizes"
Cohesion: 0.5
Nodes (4): RarityBadgeSize, large, regular, small

### Community 11 - "Rarity Model (Isolated)"
Cohesion: 1.0
Nodes (1): PlaceRarity

## Knowledge Gaps
- **51 isolated node(s):** `invalidEmail`, `weakPassword`, `missingName`, `emptyPassword`, `networkError` (+46 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Rarity Model (Isolated)`** (1 nodes): `PlaceRarity`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GameStateManager` connect `App Core & Game State` to `Collection & Celebration UI`, `Core Data Models`, `Events API & Backend`, `Social & Rewards UI`, `Location Services`?**
  _High betweenness centrality (0.187) - this node is a cross-community bridge._
- **Why does `EventsAPIService` connect `Events API & Backend` to `Core Data Models`, `App Core & Game State`, `API Protocols & Errors`?**
  _High betweenness centrality (0.180) - this node is a cross-community bridge._
- **Why does `PlacesAPIService` connect `Core Data Models` to `Collection & Celebration UI`, `Events API & Backend`, `App Core & Game State`, `API Protocols & Errors`?**
  _High betweenness centrality (0.168) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `GameStateManager` (e.g. with `Gamification Loop (Explore → Collect → Points → Rewards)` and `Dual Currency System (XP vs Points)`) actually correct?**
  _`GameStateManager` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `EventsAPIService` (e.g. with `FirestoreService` and `PlacesAPIService`) actually correct?**
  _`EventsAPIService` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `invalidEmail`, `weakPassword`, `missingName` to the rest of the system?**
  _51 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Collection & Celebration UI` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._