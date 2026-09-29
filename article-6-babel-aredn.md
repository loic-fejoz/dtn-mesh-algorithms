# Article 6 — Réseaux Maillés Proactifs et Hybridation MANET-DTN : AREDN, Babel (RFC 8966) et l'Architecture HYMAD sous Open Policy Agent

> **Série :** *Transposition d'algorithmes de routage mesh & opportunistes vers DTN (BPv7)*  
> **Articles précédents :**  
> - [Article 0 — Les Fondations du Routage DTN avec Open Policy Agent](./article-0-intro.md)  
> - [Article 1 — Transposer le Digipeating APRS (AX.25 WIDE n-N) en DTN (BPv7)](./article-1-aprs.md)  
> - [Article 2 — Dompter l'Inondation en DTN : D'Epidemic à Spray and Wait et au Flooding Géré de Meshtastic](./article-2-flood.md)  
> - [Article 3 — Routage Opportuniste et Historique des Rencontres : PRoPHET (RFC 6693) sous Open Policy Agent](./article-3-prophet.md)  
> - [Article 4 — Routage Probabiliste et Gestion de Mémoire sous Contrainte : MaxProp et ses Optimisations Théoriques (HP-MaxProp)](./article-4-maxprop.md)  
> - [Article 5 — Routage Hybride, Vecteur de Distance et Adressage Cryptographique : Reticulum (RNS) transposé en DTN](./article-5-reticulum.md)  
> **Spécifications CDDL :** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl), [prophet.cddl](./prophet.cddl), [reticulum.cddl](./reticulum.cddl) & [babel.cddl](./babel.cddl)  
> **Code des politiques :** [policies/babel/](./policies/babel/) ([ingress.rego](./policies/babel/ingress.rego), [contact.rego](./policies/babel/contact.rego), [storage.rego](./policies/babel/storage.rego), [helpers.rego](./policies/babel/helpers.rego), [constants.rego](./policies/babel/constants.rego), [babel_test.rego](./policies/babel/babel_test.rego))

---

## 1. Le Paradoxe des Îlots Haut Débit : Le Cas AREDN

Au fil des cinq premiers volets de cette série, nous nous sommes focalisés sur des liaisons radio hautement contraintes en bande passante (LoRa, AX.25 VHF/UHF, HF) ou purement opportunistes (rencontres physiques imprévues, prévisibilités PRoPHET et ordonnancement MaxProp).

Dans les opérations de secours d'urgence et de gestion de crise, un autre écosystème maillé joue un rôle vital : **AREDN (*Amateur Radio Emergency Data Network*)**.
AREDN détourne des routeurs Wi-Fi et antennes directives grand public (Ubiquiti, MikroTik, TP-Link, GL.iNet) pour les faire émettre sur les bandes radioamateurs (2.4 GHz, 3.4 GHz, 5.8 GHz) à des puissances accrues et sur des canaux réservés. Le résultat est spectaculaire : **des réseaux maillés opérationnels à plusieurs dizaines de mégabits par seconde**, capables de transporter de la VoIP, des flux de caméras IP de surveillance et des serveurs cartographiques tactiques en temps réel.

Cependant, sur le théâtre des opérations réelles (séismes, inondations, tempêtes majeures), un écueil géographique et logistique surgit inévitablement : **le partitionnement en archipel**.
- Un cluster AREDN couvre parfaitement une vallée ou un centre urbain sinistré.
- Un autre cluster AREDN est déployé autour d'un hôpital de campagne à 50 km de là.
- Entre les deux : un relief montagneux bloquant la vue directe (LOS - *Line of Sight*), une liaison dorsale micro-ondes détruite ou une panne de relais sur un sommet inaccessible.

Les protocoles maillés classiques (OLSR, Babel, B.A.T.M.A.N.) sont conçus pour acheminer des paquets IP avec une latence de quelques millisecondes. Face à une partition complète, **ils déclarent les destinations distantes inaccessibles et jettent immédiatement les paquets à la corbeille**.

C'est ici qu'intervient le paradigme **HYMAD (*Hybrid DTN-MANET routing*)** :
> **Au sein d'un îlot connecté :** Utiliser un protocole maillé proactif à haute performance (Babel / AREDN) pour garantir un acheminement instantané au prochain saut (*Next-Hop*).  
> **Entre les îlots disjoints :** Basculer sans rupture sur le Bundle Protocol v7 (BPv7) et le *Store-Carry-and-Forward* via des transporteurs mobiles (*data ferries* : véhicules de secours, drones, hélicoptères ou liaisons satellite/HF intermittentes).

---

## 2. Le Protocole Babel (RFC 8966) : Le Vecteur de Distance sans Boucle

Initialement basé sur OLSRv1 ([RFC 3626](https://www.rfc-editor.org/rfc/rfc3626.html)), le firmware AREDN a opéré une transition stratégique vers **Babel ([RFC 8966](https://www.rfc-editor.org/rfc/rfc8966.html))**.

Pourquoi préférer Babel à un protocole à état de liens comme OSPF ou OLSR ?
1. **Frugalité :** Babel ne cherche pas à synchroniser la topologie complète du graphe sur chaque nœud.
2. **Métriques réelles de liaison radio (ETX / RTT) :** Babel mesure en continu la qualité bidirectionnelle des liaisons radio via un dialogue symétrique `Hello` / `IHU` (*I Heard You*).
3. **Absence mathématique de boucle (Loop Freedom) :** Grâce à l'utilisation conjointe de la **Distance de Faisabilité (*Feasible Distance - FD*)** et de **numéros de séquence (*Seqno*)**.

```
                   Mécanisme sans boucle de Babel (RFC 8966)
                   =========================================

       +-------------------------------------------------------------+
       |             Distance de Faisabilité : FD(D)                 |
       |  (Plus petite métrique historique observée vers D)          |
       +-------------------------------------------------------------+
                                      |
                     Une annonce arrive avec la métrique M
                                      |
                         +------------+------------+
                         |                         |
                    M < FD(D)                 M >= FD(D)
                         |                         |
                         v                         v
               [ CONDITION SATISFAITE ]   [ NON FAISABLE (Risque de boucle) ]
                         |                         |
                 Route acceptée !            Route rejetée !
                 FD(D) = min(FD, M)                |
                                            Déclenchement d'un
                                            "Seqno Request" vers D
                                                   |
                                            D répond avec (seqno + 1)
                                                   |
                                            Nouvelle séquence acceptée !
```

### 2.1. La Condition de Faisabilité (*Feasibility Condition*)
Dans un vecteur de distance standard (Bellman-Ford), si un lien se rompt, deux routeurs voisins peuvent s'annoncer mutuellement des routes de plus en plus coûteuses vers la destination, créant le problème du « comptage à l'infini » (*count-to-infinity*).

Babel résout ce problème avec élégance :
- Chaque routeur maintient pour chaque destination $D$ sa **Feasible Distance** $FD(D)$, c'est-à-dire la plus faible métrique jamais enregistrée depuis le dernier reset de séquence.
- Une annonce d'un voisin avec métrique $M$ n'est adoptée que si **$M < FD(D)$**. Cette condition garantit rigoureusement qu'aucun cycle ne peut se former.

### 2.2. Les Numéros de Séquence (*Seqno*) et la Réparation Réactive
Si toutes les routes vers $D$ se dégradent (par exemple, la meilleure antenne est tombée en panne), la métrique réelle devient supérieure à $FD(D)$. La condition de faisabilité bloque alors toute mise à jour.
Plutôt que d'attendre ou de risquer une boucle :
1. Le nœud émet un message de contrôle **`Seqno Request`** à destination de $D$.
2. Le routeur cible $D$ incrémente son numéro de séquence : $s \leftarrow s + 1$.
3. $D$ diffuse une annonce `Update` avec ce nouveau numéro de séquence.
4. À la réception de ce $seqno$ supérieur, tous les nœuds intermédiaires réinitialisent leur Feasible Distance $FD(D) = M_{new}$ en toute sécurité.

---

## 3. Découplage Architectural et Spécification `babel.cddl`

### 3.1. Zéro surcoût filaire pour les données DTN
Comme pour Meshtastic ([Article 2](./article-2-flood.md)) et Reticulum ([Article 4](./article-5-reticulum.md)) :
- Les bundles de données circulant sur l'infrastructure AREDN/DTN utilisent **strictement les blocs BPv7 standards ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html))**.
- La destination est portée par l'EID standard (ex: `dtn://aredn/camera-relay-04/` ou `ipn:42.1`).
- La rupture de boucle physique d'ultime recours est déléguée au **Hop Count Block (Type 10)**.
- La déduplication repose sur le **Bundle ID canonique** `(source, time, sequence)`.

### 3.2. Spécification CDDL des Messages de Contrôle ([babel.cddl](./babel.cddl))
Les échanges de signalisation entre routeurs Babel/AREDN sont encapsulés dans le payload de bundles administratifs CBOR :

```cddl
; Message de contrôle Babel transporté dans le payload d'un bundle administratif
babel-control-bundle = {
    1 => message-type: babel-message-type,
    2 => sender-router-id: bytes .size 8,   ; Identifiant unique du routeur (64 bits)
    3 => timestamp-ms: uint,                ; Horloge DTN de création
    4 => payload: babel-payload             ; Charge utile selon le type
}

babel-message-type = &(
    msg-hello: 1,         ; Découverte de voisins et battement de cœur
    msg-ihu: 2,           ; "I Heard You" : validation bidirectionnelle (ETX)
    msg-update: 3,        ; Annonce de route proactive (prefix, seqno, metric)
    msg-route-request: 4, ; Demande d'annonce de route
    msg-seqno-request: 5  ; Requête de réinitialisation de séquence
)

; Annonce de route (Update)
update-payload = {
    1 => prefix-eid: tstr,                  ; Destination (EID ou préfixe)
    2 => router-id: bytes .size 8,          ; Router-ID d'origine
    3 => seqno: uint .size 2,               ; Numéro de séquence
    4 => metric: uint,                      ; Métrique cumulée (0 à 65535)
    5 => interval-ms: uint                  ; Durée de validité
}

; Requête urgente d'incrémentation de séquence (Seqno Request)
seqno-request-payload = {
    1 => prefix-eid: tstr,
    2 => router-id: bytes .size 8,
    3 => seqno: uint .size 2,
    4 => hop-count: uint
}
```

---

## 4. L'Hybridation HYMAD sous Open Policy Agent (OPA)

Le répertoire **[policies/babel/](./policies/babel/)** implémente la logique complète sous forme de règles déclaratives Rego.

### 4.1. Ingress : Arbitrage Bellman-Ford sans boucle ([ingress.rego](./policies/babel/ingress.rego))

À la réception d'un bundle de signalisation Babel `Update`, OPA évalue si la route doit modifier la table du routeur local :

```rego
# Ingress Règle 6 : Ingestion d'un message UPDATE Babel
decision := {
    "action": "ACCEPT_BABEL_UPDATE",
    "reason": sprintf("Babel update accepted: route to %v via %v updated (metric: %v, seqno: %v)", [
        prefix, peer_eid, total_metric, update_seqno
    ]),
    "mutations": [
        {
            "operation": "UPDATE_ROUTING_TABLE",
            "prefix_eid": prefix,
            "next_hop": peer_eid,
            "metric": total_metric,
            "seqno": update_seqno,
            "feasible_distance": total_metric,
            "expires_at_ms": input.current_dtn_time_ms + constants.default_route_expiry_ms
        },
        {
            "block_type": base_constants.block_type_hop_count,
            "operation": "SET_FIELD",
            "field": "hop_count",
            "value": hcb.hop_count + 1
        }
    ]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    helpers.is_babel_control(input.bundle)
    hcb := base_helpers.get_hop_count_block(input.bundle)
    
    update := object.get(input.ingress, "babel_update", object.get(input.bundle, "babel_update", {}))
    prefix := update.prefix_eid
    adv_metric := update.metric
    update_seqno := update.seqno
    peer_eid := object.get(input.ingress, "peer_eid", input.bundle.primary.source)
    link_cost := object.get(input.ingress, "link_cost", 10)
    total_metric := min([adv_metric + link_cost, constants.metric_infinity])
    
    existing := helpers.get_route_entry(prefix, object.get(input.node, "routing_table", {}))
    helpers.should_update_babel_route(existing, update_seqno, total_metric, input.current_dtn_time_ms)
}
```

La fonction d'aide [helpers.should_update_babel_route](./policies/babel/helpers.rego#L51-L82) applique rigoureusement les préceptes de la RFC 8966 :
- Si $seqno_{new} > seqno_{old}$ : le routeur d'origine a augmenté sa séquence, la route est mise à jour immédiatement.
- Si $seqno_{new} == seqno_{old}$ : la route n'est mise à jour que si $metric_{new} < metric_{old}$.
- Sinon : la mise à jour est ignorée (`ACCEPT_BABEL_UPDATE_NO_CHANGE`), empêchant toute propagation de métrique dégradée.

### 4.2. Contact : Forwarding Proactif ou Bascule Ferry HYMAD ([contact.rego](./policies/babel/contact.rego))

Lorsqu'un contact s'établit avec un pair, la politique distingue deux régimes :

1. **Régime Intra-Îlot (Mesh Haute Vitesse) :**
   Si la destination figure dans la table Babel locale avec une métrique valide, le bundle est routé en unicast immédiat vers le prochain saut désigné (`FORWARD_NEXT_HOP`).
2. **Régime Inter-Îlots (DTN Ferry / HYMAD) :**
   Si la destination est **inconnue ou inaccessible dans l'îlot local**, et que le pair en contact est identifié comme un vecteur mobile inter-îlots (`is_dtn_carrier == true`), OPA ordonne le déchargement immédiat vers ce ferry (`FORWARD_DTN_CARRIER`).
3. **Régime d'Isolement :**
   Si aucun vecteur inter-îlot n'est présent, le bundle n'est pas abandonné : il est conservé en mémoire tampon (`SKIP`) en attendant une opportunité future.

```rego
# Contact Règle 7 : Bascule vers le transporteur DTN inter-îlots (HYMAD)
decision := {
    "action": "FORWARD_DTN_CARRIER",
    "reason": "Destination unreachable via local AREDN mesh: offloading to opportunistic DTN inter-cluster carrier",
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_babel_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    not is_valid_route(route, input.current_dtn_time_ms)
    object.get(input.contact, "is_dtn_carrier", false) == true
}
```

### 4.3. Storage : Découverte Réactive par Route Requests ([storage.rego](./policies/babel/storage.rego))

Lors de l'audit de la mémoire de stockage, si un bundle réside dans le buffer pour une destination dont la route a expiré, OPA déclenche l'émission d'une requête de route :

```rego
decision := {
    "action": "RETAIN_AND_REQUEST_ROUTE",
    "reason": "Destination route unknown or unfeasible: trigger Babel route request",
    "mutations": [{
        "operation": "TRIGGER_BABEL_ROUTE_REQUEST",
        "prefix_eid": input.bundle.primary.destination
    }]
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_babel_control(input.bundle)
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    not is_valid_route(route, input.current_dtn_time_ms)
    object.get(input.node, "enable_babel_requests", false) == true
}
```

---

## 5. Validation par les Tests Unitaires OPA (92/92 PASS)

Une batterie de 16 tests unitaires spécifiques ([policies/babel/babel_test.rego](./policies/babel/babel_test.rego)) valide l'intégralité du comportement :
- Mise à jour de route sur nouveau seqno vs même seqno.
- Rejet des métriques dégradées (condition de faisabilité).
- Routage unicast strict vers le prochain saut.
- Bascule HYMAD vers les transporteurs DTN inter-îlots.
- Déclenchement réactif des requêtes de route depuis le stockage.

Exécution de l'ensemble de la suite de tests du projet :

```bash
opa test ./policies -v
```

```text
policies/aprs/aprs_test.rego:
  13 tests validés (digipeating AX.25, règles Dire Wolf 6.1b, 6.3c, trapping §10)
policies/babel/babel_test.rego:
  data.dtn.babel_test.test_babel_ingress_local_delivery: PASS
  data.dtn.babel_test.test_babel_ingress_blacklisted_source: PASS
  data.dtn.babel_test.test_babel_ingress_expired: PASS
  data.dtn.babel_test.test_babel_ingress_hop_limit_reached: PASS
  data.dtn.babel_test.test_babel_ingress_update_new_route: PASS
  data.dtn.babel_test.test_babel_ingress_update_newer_seqno: PASS
  data.dtn.babel_test.test_babel_ingress_update_lower_metric_same_seqno: PASS
  data.dtn.babel_test.test_babel_ingress_update_worse_metric_ignored: PASS
  data.dtn.babel_test.test_babel_ingress_data_forward: PASS
  data.dtn.babel_test.test_babel_contact_direct_destination: PASS
  data.dtn.babel_test.test_babel_contact_control_broadcast: PASS
  data.dtn.babel_test.test_babel_contact_forward_matching_next_hop: PASS
  data.dtn.babel_test.test_babel_contact_skip_non_next_hop_peer: PASS
  data.dtn.babel_test.test_babel_contact_hymad_dtn_carrier_bridging: PASS
  data.dtn.babel_test.test_babel_contact_skip_isolated_unknown_route: PASS
  data.dtn.babel_test.test_babel_storage_trigger_route_request: PASS
policies/contact_test.rego:
  5 tests validés (fondations contact CLA, split-horizon, lifetime)
policies/flood/flood_test.rego:
  17 tests validés (Spray & Wait binaire/source, Meshtastic SNR backoff et contention)
policies/maxprop/maxprop_test.rego:
  16 tests validés (coût logarithmique, pénalité de saut fluide, 2-hop gossip, cleared list)
policies/prophet/prophet_test.rego:
  16 tests validés (équations mathématiques, RIB handshake, éviction sélective)
policies/reticulum/reticulum_test.rego:
  16 tests validés (vecteur de distance cryptographique, annonces signées, Store-Carry-and-Forward)
policies/storage_test.rego:
  3 tests validés (gestion du Bundle Age Block Type 7)
--------------------------------------------------------------------------------
PASS: 108/108
```

---

## 6. Panorama Comparatif Global des 6 Protocoles

Ce sixième article vient compléter notre matrice comparative des grandes familles de routage transposées sur DTN :

| Critère | APRS AX.25 ([Art. 1](./article-1-aprs.md)) | Meshtastic ([Art. 2](./article-2-flood.md)) | PRoPHET RFC 6693 ([Art. 3](./article-3-prophet.md)) | MaxProp / HP-MaxProp ([Art. 4](./article-4-maxprop.md)) | Reticulum RNS ([Art. 5](./article-5-reticulum.md)) | AREDN / Babel / HYMAD ([Art. 6](./article-6-babel-aredn.md)) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Paradigme Fondamental** | Routage à la source & alias | Inondation gérée (*Managed Flooding*) | Opportuniste probabiliste | Dijkstra + Ordonnancement Buffer | Vecteur de distance réactif | **Hybride MANET-DTN (Proactif + Ferry)** |
| **Débit & Médium Cibles** | Trame AX.25 1200 bauds | LoRa 0.3 - 5 kbps | Bluetooth / Wi-Fi urbain | Réseaux véhiculaires & LoRa (2-hop) | Multi-médium (HF/LoRa/UDP) | **Wi-Fi Haut Débit (10-100 Mbps) + Ferries** |
| **Garantie sans boucle** | Décrément d'alias & Type 6 | Hop Count Type 10 & IDs | Hop Count Type 10 | Hop Count Type 10 | Hop Count strict & métrique croissante | **Distance de Faisabilité (FD) & Seqnos** |
| **Blocs Filaire Données DTN** | Type 200 (`trajectory_control`) | **Zéro bloc custom** (Pur BPv7) | Type 200 optionnel (`threshold`) | **Zéro bloc custom** (Pur BPv7) | **Zéro bloc custom** (Pur BPv7) | **Zéro bloc custom** (Pur BPv7) |
| **Signalisation inter-nœuds** | Aucune (broadcast aveugle) | Aucune (canaux partagés) | Handshake RIB & SV ([prophet.cddl](./prophet.cddl)) | Prob-Vector & Cleared List ([maxprop.cddl](./maxprop.cddl)) | Annonces signées ([reticulum.cddl](./reticulum.cddl)) | Hellos, IHU, Updates ([babel.cddl](./babel.cddl)) |
| **Comportement face à l'isolement** | Paquet perdu si non capté | Paquet étouffé si hors portée | Porté en mémoire jusqu'au contact | Trié et purgé par Cleared List | Garde en buffer jusqu'à annonce | **Offloading automatique vers ferry DTN** |

---

## 7. Bilan de la Série et Prochaines Frontières

En explorant successivement APRS, Spray and Wait, Meshtastic, PRoPHET, Reticulum et désormais AREDN/Babel/HYMAD, un fil conducteur s'impose avec évidence :
1. **Le Bundle Protocol v7 (RFC 9171) est un métamodèle universel.** Il unifie le transport physique sous un format canonique sans imposer d'hypothèse rigide sur la topologie sous-jacente.
2. **Open Policy Agent (OPA) transforme le routeur en système expert.** En extrayant la logique de décision du code bas niveau de la couche de convergence, nous pouvons permuter ou hybrider des algorithmes de routage radicalement différents (MANET vs DTN) d'une simple ligne de politique déclarative.
3. **Le futur du maillage d'urgence est hybride.** Les architectures de demain ne choisiront plus entre mesh temps réel et tolérance aux délais : elles composeront les deux, comme démontré avec l'hybridation AREDN-DTN.

Dans le prochain article ([Article 7](./article-7-cgr.md)), nous franchirons les limites terrestres pour explorer le standard spatial du DTN : le **Contact Graph Routing (CGR / SABR - RFC 8877)** fondé sur des fenêtres de visibilité orbitales déterministes.

---

👉 **Article suivant :** [Article 7 — Routage par Graphe de Contacts Déterministe : Contact Graph Routing (CGR / SABR - RFC 8877) sous Open Policy Agent](./article-7-cgr.md)
