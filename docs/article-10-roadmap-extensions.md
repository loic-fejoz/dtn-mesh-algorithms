# Article 10 — Perspectives et Roadmap d'Extension : Vers une Vision Panoramique du Routage DTN et l'Évolution Extensible du Plan de Contrôle

> **Auteurs :** Équipe de Recherche DTN & Systèmes Maillés Ad-Hoc  
> **Série technique :** Transposition des Algorithmes Mesh & Opportunistes vers le Bundle Protocol v7 (BPv7)  
> **Articles précédents :**  
> - [Article 0 — Les Fondations du Routage DTN avec Open Policy Agent](./article-0-intro.md)  
> - [Article 1 — Transposer le Digipeating APRS (AX.25 WIDE n-N) en DTN](./article-1-aprs.md)  
> - [Article 2 — Dompter l'Inondation en DTN : Spray and Wait et Meshtastic](./article-2-flood.md)  
> - [Article 3 — Routage Opportuniste et Historique des Rencontres : PRoPHET](./article-3-prophet.md)  
> - [Article 4 — Routage Probabiliste et Ordonnancement de Buffer : MaxProp & HP-MaxProp](./article-4-maxprop.md)  
> - [Article 5 — Routage Hybride, Vecteur de Distance et Adressage Cryptographique : Reticulum](./article-5-reticulum.md)  
> - [Article 6 — Réseaux Maillés Proactifs et Hybridation MANET-DTN : AREDN & Babel](./article-6-babel-aredn.md)  
> - [Article 7 — Routage Déterministe Spatial : Contact Graph Routing (CGR / SABR)](./article-7-cgr.md)  
> - [Article 8 — Routage Géographique et Geocasting en DTN : GeoDTN](./article-8-geodtn.md)  
> - [Article 9 — Synthèse Architecturale : Routage DTN Piloté par Politiques OPA](./article-9-synthese-architecture.md)  
> **Spécifications CDDL :** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl), [prophet.cddl](./prophet.cddl), [maxprop.cddl](./maxprop.cddl), [reticulum.cddl](./reticulum.cddl), [babel.cddl](./babel.cddl), [cgr.cddl](./cgr.cddl)

> ℹ️ **Transparence Éditoriale (Conformité EU AI Act) :** Cet article a été rédigé avec l'assistance d'une IA sous la direction éditoriale et la structuration d'un auteur humain, qui en assure la relecture, la vérification technique et la responsabilité du contenu (relecture en cours).

---

## 1. Introduction : Compléter le Panorama du Routage DTN

Au travers des Articles 0 à 9, ce projet a démontré qu'il est possible de formaliser, transposer et exécuter un spectre très large d'algorithmes de routage opportunistes et maillés au-dessus du **Bundle Protocol version 7 (BPv7 - RFC 9171)** grâce au moteur de politiques déclaratif **Open Policy Agent (OPA)**.

Cependant, la littérature scientifique consacrée aux réseaux tolérants aux délais (*Delay- and Disruption-Tolerant Networks*) est d'une richesse immense. Comme le montrent les revues de référence (notamment **Modi & Singh 2017**, le panorama du routage social par **Jain & Soares 2021**, ou les travaux de synthèse de l'**IETF DTN WG** et de la synthèse **Wikipédia**), les environnements opérationnels DTN couvrent des cas d'usage très variés :
- Les constellations de satellites et sondes deep-space (*Contact Graph Routing / CGR*).
- Les réseaux tactiques et maillés ad-hoc (*Babel, Reticulum, APRS*).
- Les réseaux véhiculaires urbains (*VANET, GeoMob, DAWN*).
- Les réseaux sociaux portés par l'humain (*Pocket Switched Networks / PSN, Bubble Rap, SimBet*).
- Les réseaux de capteurs sous-marins ou environnementaux (*UWSN, Q-Learning, LMS Filters*).

L'objectif de cet **Article 10** est double :
1. Offrir une **vue panoramique complète à 360°** de l'ensemble des familles de routage DTN identifiées dans la littérature en cartographiant ce qui est couvert par notre implémentation de référence et les extensions futures.
2. Démontrer que le **Plan de Contrôle (Control Plane)** ne doit jamais être conçu comme un schéma rigide ou monolithique, mais comme une **grammaire extensible** (définie en CDDL et JSON Schema) capable d'accueillir dynamiquement les nouvelles télémétries sans casser la rétrocompatibilité sur les liens radio contraints.

---

## 2. Cartographie Panoramique et Analyse des Lacunes (Gap Analysis)

Le tableau ci-dessous récapitule l'ensemble des familles de routage DTN identifiées dans la littérature et leur positionnement vis-à-vis de l'architecture *DTN Mesh Algorithm* :

| Famille de Routage | Protocoles Représentatifs dans la Littérature | État de Couverture dans le Dépôt | Spécifications CDDL & Politiques Rego Associées |
| :--- | :--- | :--- | :--- |
| **1. Inondation & Réplication BORNÉE / NON BORNÉE** | Epidemic, Spray & Wait, APRS Digipeating WIDE n-N, Meshtastic | **Couvert à 100%** | [article-1-aprs.md](./article-1-aprs.md), [article-2-flood.md](./article-2-flood.md)<br>`policies/aprs/`, `policies/flood/` |
| **2. Probabiliste & Historique de Rencontres** | PRoPHET (RFC 6693), MaxProp, HP-MaxProp, RAPID | **Couvert à 100%** | [article-3-prophet.md](./article-3-prophet.md), [article-4-maxprop.md](./article-4-maxprop.md)<br>`prophet.cddl`, `maxprop.cddl`, `policies/prophet/`, `policies/maxprop/` |
| **3. Vecteur de Distance & Hybride MANET-DTN** | Reticulum (RNS), Babel (RFC 8966), AREDN, HYMAD | **Couvert à 100%** | [article-5-reticulum.md](./article-5-reticulum.md), [article-6-babel-aredn.md](./article-6-babel-aredn.md)<br>`reticulum.cddl`, `babel.cddl`, `policies/reticulum/`, `policies/babel/` |
| **4. Déterministe & Spatial (Contacts Planifiés)** | Contact Graph Routing (CGR / SABR - CCSDS 734.3-B-1) | **Couvert à 100%** | [article-7-cgr.md](./article-7-cgr.md)<br>`cgr.cddl`, `policies/cgr/` |
| **5. Géographique & Cinématique** | GeoDTN (Greedy/Perimeter), Geocasting, CaD (Converge-and-Diverge), GeoMob | **Couvert par la famille** *(Extensibilité cinématique proposée en Section 3)* | [article-8-geodtn.md](./article-8-geodtn.md)<br>`policies/geodtn/`, `mesh-algo-extension-block.cddl` |
| **6. Routage Social & Communautaire** | Bubble Rap, SimBet, Label Routing, SOSIM, SEBAR, EpSoc, HiBOp | **Couvert par la famille des métriques d'utilité** *(Prise en charge des graphes $k$-cliques proposée en Section 3)* | Primitives d'utilité de `policies/maxprop/` et `policies/prophet/` |
| **7. Sensible à la Densité, au Canal & au Stockage** | GSTAR (Storage Aware), DAWN (Density Adaptive with Deadline) | **Couvert par la famille** *(Métriques de charge canal et stockage formalisées en Section 3)* | `policies/storage.rego`, `prophet.cddl` (`available-storage-bytes`) |
| **8. Routage Adaptatif & Apprentissage Automatique** | LMS Filters, Q-Learning pour DTN sous-marins (UWSN) | **Perspectives d'Extension** *(Roadmap Phase 3)* | Prédictibilité exponentielle de PRoPHET |
| **9. État de Lien Spatio-Temporel & Non-Coopératif** | DTLSR (DTN Link State), Routage par Théorie des Jeux (Incentives / Tokens / Reputation) | **Perspectives d'Extension** *(Roadmap Phase 3)* | Déduplication et filtres `blacklist_sources` de `policies/ingress.rego` |

---

## 3. Démonstration de l'Extensibilité du Plan de Contrôle

L'un des enseignements majeurs de nos travaux est la **séparation stricte entre le format sur le câble (*Wire Format*) et le contexte d'évaluation d'OPA (*Policy Evaluation Input*)**.

### A. Principe de l'Extensibilité CDDL

Pour éviter de surcharger les liens radio étroits (LoRa, VHF/AX.25, HF), les informations de signalisation sur le câble (Bloc d'Extension Type 200) ne contiennent que des primitives d'intention minimales. En revanche, les métriques mesurées localement par les modems (SNR, RSSI), l'état du nœud (batterie, mémoire) et la télémétrie des voisins sont injectées dans le plan de contrôle local sous forme de maps CBOR/JSON extensibles via des entrées optionnelles (`? key => type`).

Voici comment la spécification [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl) s'étend naturellement pour accueillir les besoins identifiés dans la littérature scientifique :

```cddl
; ==============================================================================
; EXTENSION DU CONTEXTE D'ÉVALUATION OPA (input) POUR LES NOUVELLES FAMILLES
; ==============================================================================

policy-evaluation-input = {
    bundle: bundle-context,
    node: local-node-context,
    current_dtn_time_ms: uint,
    ? ingress: ingress-telemetry-context,
    ? contact: contact-opportunity-context,
    ? social: social-network-context,          ; [NOUVEAU] Extension Routage Social
    ? kinematics: node-kinematics-context,      ; [NOUVEAU] Extension Cinématique / GeoMob
    ? channel: channel-capacity-context         ; [NOUVEAU] Extension Densité & Canal DAWN
}

; ------------------------------------------------------------------------------
; 1. EXTENSION ROUTAGE SOCIAL (Bubble Rap, SimBet, SOSIM, SEBAR)
; ------------------------------------------------------------------------------
social-network-context = {
    ? local_community_id: tstr,                 ; Identifiant du cluster k-clique local
    ? labels: [* tstr],                         ; Ensemble des labels sociaux
    ? degree_centrality: float,                ; Centralité de degré (nombre de contacts uniques)
    ? betweenness_centrality: float,           ; Centralité d'intermédiarité (pont entre communautés)
    ? interest_profile_hash: bytes .size 16,    ; Empreinte du profil d'intérêts (SOSIM)
    ? peer_social_metrics: { * tstr => {        ; Métriques sociales reçues des voisins
        community_id: tstr,
        betweenness: float,
        degree: float
    }}
}

; ------------------------------------------------------------------------------
; 2. EXTENSION CINÉMATIQUE & GÉOGRAPHIQUE AVANCÉE (CaD, GeoMob, VANET)
; ------------------------------------------------------------------------------
node-kinematics-context = {
    speed_meters_per_sec: float,                ; Vitesse scalaire instantanée
    heading_degrees: float .within (0.0 .. 360.0), ; Direction / Cap cinématique (0-360°)
    gps_error_meters: float,                    ; Incertitude de mesure GPS (précision HDOP)
    ? predicted_trajectory_vector: [float, float] ; Vecteur de déplacement estimé (dx/dt, dy/dt)
}

; ------------------------------------------------------------------------------
; 3. EXTENSION DENSITÉ DE VOISINAGE & CHARGE DE CANAL (DAWN, GSTAR)
; ------------------------------------------------------------------------------
channel-capacity-context = {
    neighbor_density_count: uint,               ; Nombre de voisins actifs à portée radio
    channel_duty_cycle_pct: float,              ; Taux d'occupation du canal radio (0 à 100%)
    ambient_rssi_floor_dbm: float,              ; Bruit de fond radio mesuré
    storage_pressure_state: &(                  ; État de pression mémoire (Buffer pressure)
        state-normal: 0,
        state-warning: 1,
        state-critical: 2,
        state-full: 3
    )
}
```

### B. Exemple Concret d'Évaluation OPA avec Métriques Étendues

Grâce à ces champs additionnels dans le Plan de Contrôle, l'écriture d'une règle OPA pour le routage **Bubble Rap** (basé sur la centralité locale et globale) ou **DAWN** (adaptatif selon la densité) devient immédiate en Rego :

```rego
package dtn.routing.bubblerap

import future.keywords.in

# Décision d'acheminement Bubble Rap
# 1. Si le voisin appartient à la communauté de la destination -> Transférer (Local Centrality)
# 2. Sinon, si le voisin a une centralité globale supérieure -> Transférer (Global Centrality)

default allow_forward = false

allow_forward {
    input.contact.peer_eid == target_peer
    peer_community := input.social.peer_social_metrics[target_peer].community_id
    dest_community := data.destinations_community_map[input.bundle.primary.destination]
    
    # Règle 1 : Entrée dans la communauté cible
    peer_community == dest_community
}

allow_forward {
    input.contact.peer_eid == target_peer
    peer_betweenness := input.social.peer_social_metrics[target_peer].betweenness
    local_betweenness := input.social.betweenness_centrality
    
    # Règle 2 : Relais vers un nœud de centralité globale supérieure (Bubble-up)
    peer_betweenness > local_betweenness
}
```

---

## 4. Alignement avec la Standardisation IETF SAND (`draft-ietf-dtn-bp-sand-04`)

Pour que ces informations de signalisation circulent entre nœuds hétérogènes sans protocole propriétaire, nous préconisons d'étendre la spécification **IETF SAND (Secure Advertisement and Neighborhood Discovery)**.

Comme détaillé dans notre document de propositions [comments-ietf-dtn-bp-sand-04.md](./comments-ietf-dtn-bp-sand-04.md), le registre IANA `SAND Routing Types` (Table 25) et les structures `nbr-metrics` (Table 26) doivent s'enrichir des clés suivantes :

```cddl
; Proposition d'extension CDDL du brouillon draft-ietf-dtn-bp-sand-04
$sand-routing-types /= &(
    sand-rtm-sabr: 1,       ; CCSDS CGR / SABR (existant)
    sand-rtm-prophet: 2,    ; PRoPHET RFC 6693
    sand-rtm-maxprop: 3,    ; MaxProp
    sand-rtm-babel: 4,      ; Babel MANET / AREDN
    sand-rtm-reticulum: 5,  ; Reticulum Cryptographic Mesh
    sand-rtm-geodtn: 6,     ; GeoDTN & Kinematic Routing
    sand-rtm-social: 7      ; Social-Based Routing (Bubble Rap / SimBet)
)

; Extension des métriques de voisinage transmises dans les Router Advertisements SAND
$nbr-metrics /= {
    nbr-metrics-base<6>, ; Métriques Géographiques & Cinématiques (GeoDTN / CaD)
    nbr-rtm-geo-latitude,
    nbr-rtm-geo-longitude,
    ? nbr-rtm-kinematic-speed,
    ? nbr-rtm-kinematic-heading
}

$nbr-metrics /= {
    nbr-metrics-base<7>, ; Métriques Sociales (Bubble Rap / SimBet)
    nbr-rtm-social-community-id,
    nbr-rtm-social-betweenness,
    nbr-rtm-social-degree
}
```

---

## 5. Roadmap d'Implémentation et d'Évolution Étape par Étape

Pour étendre l'architecture *DTN Mesh Algorithm* vers la prise en charge native de l'ensemble du panorama scientifique, nous définissons une **roadmap en 3 phases** :

```mermaid
flowchart TD
    subgraph Phase 1 : Court Terme
        P1A["Télémétrie Cinématique (Vitesse, Cap, Error GPS)"]
        P1B["Métriques de Charge Canal & Densité (DAWN/GSTAR)"]
        P1C["Delivery ACK & Purge Distribuée des Buffers"]
    end

    subgraph Phase 2 : Moyen Terme
        P2A["Extensions Routage Social (Bubble Rap, SimBet, SOSIM)"]
        P2B["Découverte de Communauté K-Clique Distribuée"]
        P2C["Distribution Dynamique du Contact Plan CGR par SAND"]
    end

    subgraph Phase 3 : Long Terme
        P3A["Apprentissage par Renforcement Distribué (Q-Learning / LMS)"]
        P3B["Routage Non-Coopératif par Jetons Cryptographiques & Réputation"]
        P3C["LSA Spatio-Temporels (DTLSR Link-State DTN)"]
    end

    Phase 1 --> Phase 2 --> Phase 3
```

### Phase 1 : Télémétrie Cinématique, Charge Canal & Purge Distribuée (Court Terme)
- **Objectif :** Enrichir `policy-evaluation-input` avec les métriques cinématiques ($\vec{v}, \theta$) et de densité locale (`neighbor_density`).
- **Livrables :** Implémentation du message `delivery-ack-payload` dans `prophet.cddl` et `maxprop.cddl` pour libérer la mémoire tampon dès qu'un bundle atteint sa destination.

### Phase 2 : Modules de Routage Social & Distribution Dynamique du Contact Plan (Moyen Terme)
- **Objectif :** Ajouter le module Rego `policies/social/` gérant la centralité et les labels de communauté.
- **Livrables :** Extension des paquets d'administration CGR pour permettre la mise à jour dynamique du plan de contact (*Contact Plan Update*) sur réseau spatial ou tactique.

### Phase 3 : Apprentissage Automatique & Théorie des Jeux (Long Terme)
- **Objectif :** Intégrer la prédiction par filtre LMS / Q-Learning (pour capteurs sous-marins UWSN) et le routage non-coopératif avec jetons d'incitation (*incentive tokens*) contre les nœuds égoïstes.
- **Livrables :** Politiques d'évaluation de réputation dans `policies/ingress.rego` et validation des preuves de relais (*Proof of Forwarding*).

---

## 6. Conclusion de la Série Technique

Avec cet **Article 10**, la série technique du projet *DTN Mesh Algorithm* fournit une **vue panoramique complète, rigoureuse et évolutive** de l'ingénierie du routage dans les réseaux tolérants aux délais et maillés contraints.

En démontrant que la complexité des algorithmes (qu'ils soient probabilistes comme PRoPHET/MaxProp, déterministes comme CGR, géométriques comme GeoDTN, cryptographiques comme Reticulum, ou sociaux comme Bubble Rap) s'exprime de manière transparente dans des **politiques déclaratives OPA au-dessus d'un Plan de Contrôle extensible**, ce travail pose les jalons des futurs standards de télécommunication tolérants aux interruptions.

---

🏁 **Fin de la série technique.**  
Consultez le code source complet, les spécifications CDDL, les politiques déclaratives et la feuille de route dans le [Dépôt du Projet DTN Mesh Algorithm](./index.md).
