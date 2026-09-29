# Article 7 — Le Routage Déterministe Spatial : Contact Graph Routing (CGR / SABR - RFC 8877) sous Open Policy Agent

> **Série :** *Transposition d'algorithmes de routage mesh & opportunistes vers DTN (BPv7)*  
> **Articles précédents :**  
> - [Article 0 — Les Fondations du Routage DTN avec Open Policy Agent](./article-0-intro.md)  
> - [Article 1 — Transposer le Digipeating APRS (AX.25 WIDE n-N) en DTN (BPv7)](./article-1-aprs.md)  
> - [Article 2 — Dompter l'Inondation en DTN : D'Epidemic à Spray and Wait et au Flooding Géré de Meshtastic](./article-2-flood.md)  
> - [Article 3 — Routage Opportuniste et Historique des Rencontres : PRoPHET (RFC 6693) sous Open Policy Agent](./article-3-prophet.md)  
> - [Article 4 — Routage Probabiliste et Gestion de Mémoire sous Contrainte : MaxProp et ses Optimisations Théoriques (HP-MaxProp)](./article-4-maxprop.md)  
> - [Article 5 — Routage Hybride, Vecteur de Distance et Adressage Cryptographique : Reticulum (RNS) transposé en DTN](./article-5-reticulum.md)  
> - [Article 6 — Réseaux Maillés Proactifs et Hybridation MANET-DTN : AREDN, Babel (RFC 8966) et l'Architecture HYMAD sous Open Policy Agent](./article-6-babel-aredn.md)  
> **Spécifications CDDL :** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl), [prophet.cddl](./prophet.cddl), [maxprop.cddl](./maxprop.cddl), [reticulum.cddl](./reticulum.cddl), [babel.cddl](./babel.cddl) & [cgr.cddl](./cgr.cddl)  
> **Code des politiques :** [policies/cgr/](./policies/cgr/) ([ingress.rego](./policies/cgr/ingress.rego), [contact.rego](./policies/cgr/contact.rego), [storage.rego](./policies/cgr/storage.rego), [helpers.rego](./policies/cgr/helpers.rego), [constants.rego](./policies/cgr/constants.rego), [cgr_test.rego](./policies/cgr/cgr_test.rego))

---

## 1. De l'Aléatoire Terrestre au Déterminisme Céleste

Jusqu'à présent, tous les algorithmes étudiés dans cette série partageaient une hypothèse fondamentale : **l'imprévisibilité ou l'estimation statistique des contacts**.
- En APRS et Meshtastic, les transmissions se font au fil de l'eau sur des canaux partagés.
- En Spray & Wait, PRoPHET et MaxProp, les nœuds découvrent leurs voisins lors de rencontres opportunistes régies par les mouvements humains ou véhiculaires.
- En Reticulum et Babel, les routes émergent dynamiquement par annonces ou sondages de liens radio fluctuants.

Cependant, le berceau historique du **Delay-Tolerant Networking** n'est pas terrestre : c'est la conquête spatiale et l'**Internet Interplanétaire (IPN)** imaginé par Vint Cerf, Adrian Hooke et Scott Burleigh au sein du NASA Jet Propulsion Laboratory (JPL).

Dans l'espace interplanétaire (missions martiennes, sondes vers Jupiter, constellations de satellites en orbite basse LEO, orbiteurs lunaires Artemis) :
1. **Les distances sont titanesques :** Le temps de propagation de la lumière à l'aller simple (*One-Way Light Time - OWLT*) entre la Terre et Mars varie de **3 à 22 minutes**.
2. **Les ruptures de liaison sont périodiques et prévisibles :** Un atterrisseur au fond d'un cratère martien ne peut communiquer avec un orbiteur que lorsque ce dernier survole son zénith (fenêtre de visibilité de 10 à 15 minutes, deux fois par sol martien). Une station sol du Deep Space Network (DSN) à Goldstone, Madrid ou Canberra n'est pointée vers une sonde que selon un créneau d'antenne réservé des semaines à l'avance.
3. **Les lois de Kepler dictent la topologie :** La trajectoire des astres et des engins spatiaux est connue à la milliseconde près.

Dans ce contexte, attendre une « rencontre opportuniste » ou inonder aveuglément le vide spatial serait absurde. L'algorithme roi du DTN spatial est **Contact Graph Routing (CGR)**, standardisé par l'IRTF et l'IETF dans la **[RFC 8877](https://www.rfc-editor.org/rfc/rfc8877.html)**.

---

## 2. Les Piliers Théoriques de la RFC 8877

CGR ne construit pas une table de routage sur un graphe spatial statique, mais sur un **graphe spatio-temporel (*Time-Expanded Graph*)**.

```
             Représentation Spatio-Temporelle d'un Contact Plan
             ===================================================

  Nœud Terre  [ Fenêtre 1 : 00:00 -> 00:30 ]
                        \  (Débit : 2 Mbps, OWLT : 8 min)
                         v
  Orbiteur Mars          [ Fenêtre 2 : 01:15 -> 01:30 ]
                                 \  (Débit : 500 kbps, OWLT : 0.05 s)
                                  v
  Rover Mars Surface              [ Réception finale : EDT = 01:25 ]
```

### 2.1. Le Contact Plan (Calendrier de Contacts)
Le cœur de CGR est le **Contact Plan**, un registre déterministe partagé par tous les nœuds de la mission :
- **Contacts planifiés :** Un tuple $(\text{Source}, \text{Dest}, t_\text{start}, t_\text{end}, \text{Rate}, \text{Capacité})$ spécifiant avec certitude qu'une liaison point-à-point sera active entre les instants $t_\text{start}$ et $t_\text{end}$ à un débit précis.
- **Plages de distance (*Ranges*) :** Spécifient le délai physique de propagation $OWLT(t)$ (temps que met le signal électromagnétique pour parcourir la distance à la vitesse de la lumière).

### 2.2. L'Arbre de Dijkstra Spatio-Temporel et l'EDT
Lorsqu'un bundle pour `dtn://mars-rover/` est soumis au routeur CGR terrestre :
1. CGR projette les contacts futurs dans le temps.
2. Il applique l'algorithme de Dijkstra où le coût d'une arête n'est pas une distance physique, mais le **temps d'arrivée au plus tôt (*Earliest Delivery Time - EDT*)**.
3. Pour chaque saut, le paquet ne peut partir qu'à $t \ge \max(\text{Arrivée}, t_\text{start})$ et arrivera au nœud suivant à $t_\text{arrivée} = t_\text{départ} + OWLT + \frac{\text{Taille}}{\text{Débit}}$.

### 2.3. Gestion des Volumes et Rejet Préventif Déterministe
Chaque fenêtre de contact possède une capacité finie en octets :
$$\text{Capacité} = (t_\text{end} - t_\text{start}) \times \text{Rate}$$
À chaque bundle planifié sur un contact, la capacité restante est décrémentée.
Si la capacité d'une fenêtre est épuisée, CGR oriente les bundles excédentaires vers la fenêtre suivante ou vers un relais alternatif.

**L'avantage massif de CGR par rapport aux protocoles terrestres :**
Si l'évaluation CGR démontre que la meilleure séquence de contacts aboutit à un $EDT > \text{Bundle Lifetime}$, **le bundle est détruit immédiatement à la source ou au premier relais !** Il est mathématiquement impossible qu'il parvienne à destination avant son expiration : l'abandonner préventivement évite de gaspiller de précieux mégaoctets de stockage bord et de bande passante radioélectrique.

---

## 3. Spécification Filaire CDDL : `cgr.cddl`

Les bundles de données voyagent sous forme standard BPv7 ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html)).
La diffusion et la révocation des calendriers de contact entre centres de contrôle et sondes sont spécifiées en CBOR dans **[cgr.cddl](./cgr.cddl)** :

```cddl
; Message de contrôle CGR transporté dans le payload d'un bundle administratif
cgr-control-bundle = {
    1 => message-type: cgr-message-type,
    2 => issuer-eid: tstr,                  ; EID de l'autorité émettrice
    3 => timestamp-ms: uint,                ; Horloge DTN d'émission
    4 => payload: cgr-payload               ; Charge utile
}

cgr-message-type = &(
    msg-contact-plan-update: 1, ; Mise à jour de fenêtres planifiées
    msg-contact-plan-revoke: 2, ; Annulation de contact (panne d'émetteur)
    msg-range-update: 3         ; Mise à jour de distance OWLT
)

scheduled-contact = {
    1 => contact-id: uint,                  ; Identifiant unique de contact
    2 => from-eid: tstr,                    ; Nœud émetteur
    3 => to-eid: tstr,                      ; Nœud récepteur
    4 => start-time-ms: uint,               ; Début de la fenêtre
    5 => end-time-ms: uint,                 ; Fin de la fenêtre
    6 => data-rate-bps: uint,               ; Débit de transmission
    ? 7 => max-capacity-bytes: uint,        ; Capacité totale
    ? 8 => confidence: float                ; Indice de confiance
}
```

---

## 4. Modélisation Déclarative sous Open Policy Agent (OPA)

Le répertoire **[policies/cgr/](./policies/cgr/)** implémente les décisions spatio-temporelles.

### 4.1. Contact : Transmission Synchronisée sur la Fenêtre ([contact.rego](./policies/cgr/contact.rego))

Contrairement aux protocoles terrestres où la présence d'un pair autorise l'émission immédiate, CGR exige trois conditions simultanées :
1. Le pair correspond au prochain saut désigné par la séquence CGR optimale (`input.contact.peer_eid == path.next_hop_eid`).
2. L'horloge DTN actuelle se situe strictement à l'intérieur de la fenêtre de contact active ($t_\text{start} \le \text{Now} \le t_\text{end}$).
3. La capacité résiduelle de la fenêtre est supérieure ou égale à la taille du bundle.

```rego
# Règle Contact 5 : Transmission déterministe lors d'une fenêtre active
decision := {
    "action": "FORWARD_CGR_SCHEDULED",
    "reason": sprintf("CGR contact window active with %v (EDT: %v, remaining capacity: %v)", [
        path.next_hop_eid,
        path.earliest_delivery_time_ms,
        path.remaining_capacity_bytes
    ]),
    "mutations": [{
        "operation": "DECREMENT_CONTACT_CAPACITY",
        "contact_id": path.first_contact_id,
        "bytes": bundle_size
    }]
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_cgr_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    
    path := helpers.get_cgr_path(input.bundle.primary.destination, object.get(input.node, "cgr_routes", {}))
    path != null
    input.contact.peer_eid == path.next_hop_eid
    helpers.is_path_viable(path, input.bundle, input.current_dtn_time_ms)
    
    contact := object.get(input.contact, "scheduled_contact", null)
    contact != null
    helpers.is_contact_active(contact, input.current_dtn_time_ms)
    
    bundle_size := object.get(input.bundle, "total_size_bytes", 1024)
}
```

Si le pair est en vue mais que la fenêtre n'est pas encore ouverte (par exemple, pointage d'antenne non verrouillé) ou que la capacité est épuisée, OPA retourne `action: "SKIP"`, maintenant le bundle en stockage.

### 4.2. Storage : Élimination Préventive des Bundles Inviables ([storage.rego](./policies/cgr/storage.rego))

Lors de la maintenance périodique des mémoires de stockage :

```rego
# Règle Storage 3 : Abandon préventif déterministe
decision := {
    "action": "DROP_INFEASIBLE_SCHEDULE",
    "reason": "Deterministic CGR check: Earliest Delivery Time exceeds bundle lifetime",
    "generate_status_report": base_helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_cgr_control(input.bundle)
    path := helpers.get_cgr_path(input.bundle.primary.destination, object.get(input.node, "cgr_routes", {}))
    is_path_impossible(path, input.bundle)
}

is_path_impossible(path, bundle) if {
    path != null
    creation_time := bundle.primary.creation_timestamp.time
    lifetime := bundle.primary.lifetime
    path.earliest_delivery_time_ms > (creation_time + lifetime)
}
```

Cette règle illustre la puissance du modèle déclaratif OPA : un paquet voué à l'échec est éliminé des jours ou des semaines avant son expiration théorique, protégeant les tampons mémoires des satellites contre la saturation.

---

## 5. Validation par les Tests Unitaires OPA (124/124 PASS)

Une suite de 16 tests unitaires spécifiques ([policies/cgr/cgr_test.rego](./policies/cgr/cgr_test.rego)) couvre l'ensemble des cas d'usage CGR :
- Validation des fenêtres temporelles actives vs futures vs expirées.
- Décrément de capacité résiduelle lors de la planification d'un envoi.
- Refus de transmission si la taille du bundle excède la capacité restante de la fenêtre.
- Abandon préventif déterministe lorsque l'EDT dépasse la durée de vie ($EDT > \text{Lifetime}$).

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
policies/ingress_test.rego:              6 tests validés
policies/maxprop/maxprop_test.rego:     16 tests validés
policies/prophet/prophet_test.rego:     16 tests validés
policies/reticulum/reticulum_test.rego: 16 tests validés
policies/storage_test.rego:              3 tests validés
--------------------------------------------------------------------------------
PASS: 124/124
```

---

## 6. Synthèse Comparative : Opportuniste vs Déterministe

| Critère | Approches Opportunistes (PRoPHET / MaxProp) | Approche Déterministe Spatial (CGR RFC 8877) |
| :--- | :--- | :--- |
| **Environnement Cible** | Réseaux urbains, véhicules, capteurs ad-hoc | Espace lointain (Terre, Lune, Mars), constellations LEO |
| **Connaissance des Contacts** | Découverte en temps réel, probabiliste | Calendrier prédictif déterministe (*Contact Plan*) |
| **Gestion du Délai de Propagation** | Négligeable (ms radio) | **Critique : Intégration du OWLT** (minutes-lumière) |
| **Graphe de Routage** | Topologie instantanée ou historique local | **Graphe Spatio-Temporel** orienté dans le futur |
| **Politique de Rétention Buffer** | Éviction réactive en cas de saturation | **Abandon préventif déterministe** si $EDT > \text{Lifetime}$ |
| **Gestion de la Capacité** | Inconnue avant contact | Volume comptabilisé et décrémenté par fenêtre |

---

## 7. Perspectives : Vers le Routage Géographique et le Geocasting

Avec CGR, nous avons résolu le routage planifié lorsque le temps et les orbites gouvernent le réseau.

Mais que se passe-t-il sur Terre lorsque nous n'avons ni calendrier préétabli, ni adresses IP, ni même de routeurs préalablement cartographiés, mais que **seule la position géographique compte** (recherche de victimes par drones, balises d'urgence, capteurs de séismes) ?

Dans le prochain article ([Article 8](./article-8-geodtn.md)), nous explorerons le **Routage Géographique et le Geocasting (GeoDTN / GPSR-DTN)** en exploitant la primitive `spatial_scope` de notre spécification CDDL !

---

👉 **Article suivant :** [Article 8 — Routage Géographique et Geocasting en DTN : GeoDTN et Greedy-Carry-and-Forward sous Open Policy Agent](./article-8-geodtn.md)
