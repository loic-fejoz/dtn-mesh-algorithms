# Article 8 — Le Routage Géographique et le Geocasting : GeoDTN et le Franchissement des Vides sous Open Policy Agent

> **Série :** *Transposition d'algorithmes de routage mesh & opportunistes vers DTN (BPv7)*  
> **Articles précédents :**  
> - [Article 0 — Les Fondations du Routage DTN avec Open Policy Agent](./article-0-intro.md)  
> - [Article 1 — Transposer le Digipeating APRS (AX.25 WIDE n-N) en DTN (BPv7)](./article-1-aprs.md)  
> - [Article 2 — Dompter l'Inondation en DTN : D'Epidemic à Spray and Wait et au Flooding Géré de Meshtastic](./article-2-flood.md)  
> - [Article 3 — Routage Opportuniste et Historique des Rencontres : PRoPHET (RFC 6693) sous Open Policy Agent](./article-3-prophet.md)  
> - [Article 4 — Routage Probabiliste et Gestion de Mémoire sous Contrainte : MaxProp et ses Optimisations Théoriques (HP-MaxProp)](./article-4-maxprop.md)  
> - [Article 5 — Routage Hybride, Vecteur de Distance et Adressage Cryptographique : Reticulum (RNS) transposé en DTN](./article-5-reticulum.md)  
> - [Article 6 — Réseaux Maillés Proactifs et Hybridation MANET-DTN : AREDN, Babel (RFC 8966) et l'Architecture HYMAD sous Open Policy Agent](./article-6-babel-aredn.md)  
> - [Article 7 — Le Routage Déterministe Spatial : Contact Graph Routing (CGR / SABR - CCSDS 734.3-B-1) sous Open Policy Agent](./article-7-cgr.md)  
> **Spécifications CDDL :** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl), [prophet.cddl](./prophet.cddl), [maxprop.cddl](./maxprop.cddl), [reticulum.cddl](./reticulum.cddl), [babel.cddl](./babel.cddl) & [cgr.cddl](./cgr.cddl)  
> **Code des politiques :** [policies/geodtn/](./policies/geodtn/) ([ingress.rego](./policies/geodtn/ingress.rego), [contact.rego](./policies/geodtn/contact.rego), [storage.rego](./policies/geodtn/storage.rego), [helpers.rego](./policies/geodtn/helpers.rego), [constants.rego](./policies/geodtn/constants.rego), [geodtn_test.rego](./policies/geodtn/geodtn_test.rego))

> ℹ️ **Transparence Éditoriale (Conformité EU AI Act) :** Cet article a été rédigé avec l'assistance d'une IA sous la direction éditoriale et la structuration d'un auteur humain, qui en assure la relecture, la vérification technique et la responsabilité du contenu (relecture en cours).

---

## 1. La Coordonnée comme Seule Adresse

Dans les sept premiers articles de notre série, nous avons examiné le routage sous presque toutes ses formes :
- Par alias d'acheminement ([APRS](./article-1-aprs.md)).
- Par diffusion et contention physique ([Meshtastic & Spray & Wait](./article-2-flood.md)).
- Par apprentissage statistique de sociabilité ([PRoPHET](./article-3-prophet.md)).
- Par calcul de plus court chemin probabiliste et ordonnancement de buffer ([MaxProp](./article-4-maxprop.md)).
- Par vecteurs de distance cryptographiques auto-souverains ([Reticulum](./article-5-reticulum.md)).
- Par métriques radio proactives sans boucle et hybridation îlots ([AREDN / Babel](./article-6-babel-aredn.md)).
- Par calendrier spatio-temporel céleste déterministe ([CGR](./article-7-cgr.md)).

Mais imaginons le scénario d'une catastrophe naturelle majeure : un séisme de grande ampleur ou un gigantesque feu de forêt.
- Les infrastructures cellulaires et terrestres sont pulvérisées.
- Des centaines de sauveteurs, de drones autonomes de reconnaissance et de balises de détresse de victimes s'activent sur le terrain.
- Aucun annuaire central n'existe : **un secouriste ou un drone ne connaît ni l'EID ni l'adresse IP de la victime ou de l'équipe médicale la plus proche**.
- La seule information connue est géographique : « *Acheminer cette alerte médicale vers la zone de détresse aux coordonnées $(45.75^\circ\text{N}, 4.85^\circ\text{E})$, dans un rayon de 1 kilomètre* ».

C'est le royaume du **Routage Géographique (*Geographic Routing*)** et de la **Diffusion Géographique Ciblée (*Geocasting*)**.

---

## 2. Le Talon d'Achille des MANETs : Le Piège du Minimum Local

Dans les réseaux maillés ad-hoc sans fil (MANETs), l'algorithme géographique de référence est **GPSR (*Greedy Perimeter Stateless Routing*)**, formulé par Brad Karp et H. T. Kung (2000).

GPSR repose sur un principe intuitif nommé **Routage Glouton (*Greedy Forwarding*)** :
> Chaque nœud transmet le paquet au voisin physique qui minimise la distance euclidienne vers les coordonnées de destination.

```
                  Le Piège du Minimum Local (Void) en MANET
                  ==========================================

                          [ Cible Géographique ]
                                    ^
                                    |
                            (Obstacle / Vide)
                                    |
                            [ Nœud Relais A ]
                               /         \
                              v           v
                        [ Voisin B ]    [ Voisin C ]
                  (Plus loin de la cible que A !)
```

Cependant, le routage glouton souffre d'un écueil fondamental : **le minimum local (*Local Void*)**.
Si le nœud porteur $A$ est plus proche de la cible que tous ses voisins immédiats (par exemple face à une falaise, un lac ou une zone inhabitée sans relais), **l'algorithme glouton se retrouve dans une impasse**.

Dans les réseaux IP/MANET classiques :
- GPSR tente de basculer en mode contournement (*Perimeter Routing / Face Routing*), qui consiste à longer le périmètre du vide selon la règle de la main droite sur un graphe planaire (RNG ou Gabriel Graph).
- En pratique (propagation radio réelle avec obstacles, interférences et topologie 3D), **la planarisation échoue presque systématiquement**, provoquant des boucles infinies et l'abandon pur et simple des paquets.

---

## 3. La Rupture GeoDTN : Le Greedy-Carry-and-Forward

L'hybridation avec le **Bundle Protocol v7** balaye d'un revers de main la complexité fragile du Face Routing :

> **En GeoDTN, un minimum local n'est pas une panne : c'est simplement une opportunité de stockage (*Carry Phase*) !**

Lorsqu'un nœud porteur $A$ atteint un vide topologique où aucun voisin n'est plus proche de la cible :
1. Le nœud n'abandonne pas le bundle.
2. Il ne déclenche pas d'algorithme de planarisation périlleux.
3. Il conserve le bundle dans sa mémoire tampon DTN (**`action: "SKIP"` / Greedy-Carry-and-Forward**).
4. Le nœud se déplace physiquement (ou attend qu'un drone, un véhicule de secours ou un autre piéton arrive dans son champ radio).
5. Dès qu'un nouveau contact offre une position plus proche de la cible, le mode glouton reprend instantanément.

```
       +-------------------------------------------------------------+
       |         Bundle émis vers (Target_Lat, Target_Lon)           |
       +-------------------------------------------------------------+
                                      |
                                      v
       +-------------------------------------------------------------+
       |   Existe-t-il un voisin plus proche de la cible que moi ?    |
       +-------------------------------------------------------------+
                    /                                    \
                [ OUI ]                                [ NON ]
                   |                                      |
         Routage Glouton (Greedy)               Minimum Local Détecté
       FORWARD_GREEDY vers le voisin                      |
                                                Garde DTN active
                                            (Greedy-Carry-and-Forward)
                                            Bundle conservé en mémoire
                                                          |
                                            Mobilité physique d'un nœud
                                                          |
                                            Nouveau voisin plus proche !
                                                          |
                                            Reprise du routage glouton
```

---

## 4. Geocasting : De l'Acheminement Unicast à l'Inondation de Zone

Le routage géographique distingue deux phases majeures :
1. **Phase de Transit Glouton (*Ingress to Perimeter*) :** Tant que le paquet se trouve en dehors du cercle de destination ($Distance > R$), il est routé en unicast pur de proche en proche vers le centre géographique.
2. **Phase de Diffusion Intra-Zone (*In-Zone Geocast Flooding*) :** Dès que le bundle franchit le rayon $R$ du périmètre cible, il bascule en diffusion locale : **tous les nœuds situés à l'intérieur de la zone géographique s'échangent et livrent le message localement**, garantissant que toutes les équipes de secours présentes dans la zone reçoivent l'ordre ou l'alerte.

---

## 5. Spécification Filaire CDDL : La Facette `spatial_scope`

Dans l'[Article 0](./article-0-intro.md), nous avions spécifié un bloc d'extension générique modulaire (**Type 200** dans la plage expérimentale IANA de la [RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html)).

La **facette 5 (`spatial_scope`)** de **[mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl#L41-L47)** formalise précisément cette charge utile :

```cddl
mesh-routing-data = {
    ? 1 => legacy-bridge-id: (bytes / uint),
    ? 2 => replication-control: replication-control,
    ? 3 => trajectory-control: trajectory-control,
    ? 4 => opportunistic-threshold: float,
    ? 5 => spatial-scope: spatial-scope
}

spatial-scope = {
    1 => center-lat-deg: float,       ; Latitude en degrés décimaux (-90.0 à +90.0)
    2 => center-lon-deg: float,       ; Longitude en degrés décimaux (-180.0 à +180.0)
    ? 3 => center-alt-meters: float,  ; Altitude en mètres
    ? 4 => radius-meters: float,      ; Rayon d'action en mètres (0 = point exact)
    ? 5 => radius-deg: float          ; Rayon en degrés pour calculs rapides
}
```

- Si `radius == 0` : Routage géographique point-à-point vers une position précise.
- Si `radius > 0` : Geocast vers une zone circulaire (périmètre de secours ou zone d'urgence).
- La déduplication est assurée par le **Bundle ID canonique** `(source, time, sequence)` et la limitation de propagation par le **Hop Count Block (Type 10)**.

---

## 6. Modélisation Déclarative sous Open Policy Agent (OPA)

Le répertoire **[policies/geodtn/](./policies/geodtn/)** formalise les règles d'arbitrage spatial.

### 6.1. Ingress : Livraison Locale Géographique ([ingress.rego](./policies/geodtn/ingress.rego))

À l'entrée, un bundle est livré localement si l'EID correspond, **OU si le bundle est un Geocast et que le nœud local est physiquement situé à l'intérieur du périmètre spatial** :

```rego
# Règle Ingress 2 : Livraison locale si EID ou position géographique concordante
decision := {
    "action": "DELIVER_LOCAL",
    "reason": "Local delivery: node matches EID or is inside targeted Geocast spatial scope",
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    helpers.is_local_destination(input.bundle, input.node)
}
```

La fonction [helpers.is_local_destination](./policies/geodtn/helpers.rego#L37-L50) calcule la distance euclidienne :
$$\text{dist}^2 = (\text{lat}_\text{node} - \text{lat}_\text{center})^2 + (\text{lon}_\text{node} - \text{lon}_\text{center})^2 \le R^2$$

### 6.2. Contact : Forwarding Glouton vs Franchissement de Vide ([contact.rego](./policies/geodtn/contact.rego))

Lorsqu'un contact s'établit avec un voisin :

1. **Diffusion dans la zone Geocast :** Si les deux nœuds sont déjà à l'intérieur de la zone cible, le bundle est rediffusé (`FORWARD_GEOCAST_IN_ZONE`).
2. **Routage Glouton :** Si le pair est plus proche des coordonnées cibles que le nœud local, transmission immédiate (`FORWARD_GREEDY`).
3. **Franchissement de Vide (Carry-and-Forward) :** Si aucun voisin n'est plus proche, OPA ordonne la rétention en mémoire (`SKIP`), évitant toute boucle stérile.

```rego
# Règle Contact 5 : Routage Glouton (Greedy Forwarding)
decision := {
    "action": "FORWARD_GREEDY",
    "reason": "Greedy geographic forwarding: peer is closer to target spatial coordinates",
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    input.contact.peer_eid != input.bundle.primary.destination
    not is_in_zone_geocast_active(input)
    
    scope := helpers.get_spatial_scope(input.bundle)
    scope != null
    
    my_coords := object.get(input.node, "coordinates", null)
    peer_coords := object.get(input.contact, "coordinates", null)
    my_coords != null
    peer_coords != null
    
    helpers.is_peer_closer(peer_coords, my_coords, scope.center_lat_deg, scope.center_lon_deg)
}

# Règle Contact 6 : Minimum local (Local Void) -> Rétention DTN
decision := {
    "action": "SKIP",
    "reason": "Local minimum void: peer is not closer to target coordinates, holding bundle (Greedy-Carry-and-Forward)",
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    input.contact.peer_eid != input.bundle.primary.destination
    not is_in_zone_geocast_active(input)
    
    scope := helpers.get_spatial_scope(input.bundle)
    scope != null
    
    my_coords := object.get(input.node, "coordinates", null)
    peer_coords := object.get(input.contact, "coordinates", null)
    
    is_not_closer(peer_coords, my_coords, scope)
}
```

---

## 7. Validation par les Tests Unitaires OPA (140/140 PASS)

Une batterie de 16 tests unitaires spécifiques ([policies/geodtn/geodtn_test.rego](./policies/geodtn/geodtn_test.rego)) couvre l'ensemble des comportements géographiques :
- Livraison locale d'un Geocast basée uniquement sur la localisation GPS du nœud.
- Progression gloutonne vers un pair se rapprochant de la cible.
- Détection du vide (*local void*) et bascule en stockage temporaire (*Greedy-Carry-and-Forward*).
- Diffusion broadcast intra-zone dès l'atteinte du périmètre géographique.
- Respect du *Split Horizon* (Type 6) et du *Hop Count* (Type 10).

Exécution de la suite complète du dépôt :

```bash
opa test ./policies -v
```

```text
policies/aprs/aprs_test.rego:           13 tests validés
policies/babel/babel_test.rego:         16 tests validés
policies/cgr/cgr_test.rego:             16 tests validés
policies/contact_test.rego:              5 tests validés
policies/flood/flood_test.rego:         17 tests validés
policies/geodtn/geodtn_test.rego:       16 tests validés
policies/ingress_test.rego:              6 tests validés
policies/maxprop/maxprop_test.rego:     16 tests validés
policies/prophet/prophet_test.rego:     16 tests validés
policies/reticulum/reticulum_test.rego: 16 tests validés
policies/storage_test.rego:              3 tests validés
--------------------------------------------------------------------------------
PASS: 140/140
```

---

## 8. La Grande Table Périodique du Routage DTN

Avec ce huitième et dernier article fondamental, notre série boucle l'exploration exhaustive des grands paradigmes de routage :

| Algorithme | Paradigme | Format d'Adressage | Métrique d'Arbitrage | Gestion des Pannes & Vides |
| :--- | :--- | :--- | :--- | :--- |
| **APRS ([Art. 1](./article-1-aprs.md))** | Routage à la source & alias | Indicatifs Radio (`NOCALL`) | Consommation d'alias (`WIDE-n-N`) | Perte du paquet |
| **Meshtastic ([Art. 2](./article-2-flood.md))** | Inondation gérée | NodeNum 32 bits | Backoff SNR physique | Inondation redondante |
| **Spray & Wait ([Art. 2](./article-2-flood.md))** | Quotas stricts | EID URI canonique | Division de quota binaire $L/2$ | Attente directe (Phase Wait) |
| **PRoPHET ([Art. 3](./article-3-prophet.md))** | Probabiliste d'historique | EID URI canonique | Prévisibilité de rencontre $P_{(A, B)}$ | Éviction par faible utilité |
| **MaxProp ([Art. 4](./article-4-maxprop.md))** | Dijkstra & Tri de Buffer | EID URI canonique | Coût log $-\log(P) + 0.01 \times \text{Hops}$ | Purge par Cleared List |
| **Reticulum ([Art. 5](./article-5-reticulum.md))** | Vecteur de distance réactif | Hash cryptographique 16 octets | Sauts stricts via Annonces signées | Garde en buffer DTN |
| **Babel / AREDN ([Art. 6](./article-6-babel-aredn.md))** | Proactif & Hybride MANET | EID / Sous-réseau | Distance de Faisabilité (FD) & ETX | Passerelle ferry **HYMAD** |
| **CGR ([Art. 7](./article-7-cgr.md))** | Déterministe spatial | EID interplanétaire | *Earliest Delivery Time* (EDT) | Abandon préventif déterministe |
| **GeoDTN ([Art. 8](./article-8-geodtn.md))** | Géographique & Geocasting | Coordonnées spatiales (lat, lon) | Distance euclidienne vers la cible | **Greedy-Carry-and-Forward** |

---

## 9. Conclusion de la Série

La combinaison du **Bundle Protocol version 7 ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html))** et d'un moteur de politiques déclaratif comme **Open Policy Agent (OPA)** réalise une promesse longtemps attendue par l'ingénierie des réseaux :

1. **L'émancipation vis-à-vis des adresses IP :** Que l'adresse soit un indicatif radio, un hash de clé publique Ed25519, un point d'orbite martienne ou des coordonnées GPS, le Primary Block de BPv7 la transporte avec la même rigueur canonique.
2. **Le découplage total de la logique :** Le moteur de transport (gestion des interfaces radio LoRa/VHF/Wi-Fi, sérialisation CBOR et stockage disque) n'a plus à être réécrit pour chaque nouvel algorithme. Une simple modification de politique Rego transforme un routeur spatial CGR en balise de secours GeoDTN ou en nœud souverain Reticulum.
3. **L'invulnérabilité face aux ruptures :** Qu'il s'agisse de minutes-lumière interplanétaires ou de reliefs montagneux terrestres, le principe fondamental du *Store-Carry-and-Forward* garantit qu'aucune donnée n'est sacrifiée.

---

👉 **Article suivant (Synthèse & Perspectives) :** [Article 9 — Synthèse Architecturale : Routage DTN Piloté par Politiques OPA, Bloc d'Extension Modulaire et Unification du Plan de Contrôle](./article-9-synthese-architecture.md)
