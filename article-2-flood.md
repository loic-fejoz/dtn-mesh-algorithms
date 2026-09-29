# Article 2 — Dompter l'Inondation en DTN : D'Epidemic à Spray and Wait et au Flooding Géré de Meshtastic

> **Série :** *Transposition d'algorithmes de routage mesh & opportunistes vers DTN (BPv7)*  
> **Articles précédents :**  
> - [Article 0 — Les Fondations du Routage DTN avec Open Policy Agent](./article-0-intro.md)  
> - [Article 1 — Transposer le Digipeating APRS (AX.25 WIDE n-N) en DTN (BPv7)](./article-1-aprs.md)  
> **Spécification CDDL :** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl)  
> **Code des politiques :** [policies/flood/](./policies/flood/) ([ingress.rego](./policies/flood/ingress.rego), [contact.rego](./policies/flood/contact.rego), [helpers.rego](./policies/flood/helpers.rego), [constants.rego](./policies/flood/constants.rego), [flood_test.rego](./policies/flood/flood_test.rego))

---

## 1. La Tension Fondamentale de l'Inondation en Réseau Contraint

Dans les réseaux tolérants aux délais (DTN) et les réseaux maillés ad-hoc sans infrastructure, le routage est confronté à un dilemme permanent entre :
1. **La minimisation du délai d'acheminement** vers la destination.
2. **La préservation des ressources critiques** : énergie de la batterie, occupation du tampon mémoire (*buffer*) et temps d'occupation spectral radio (*duty cycle* LoRa, collisions CSMA).

### 1.1. L'illusion d'Epidemic Routing
Introduit par Vahdat et Becker en 2000, l'**Epidemic Routing** repose sur une inondation opportuniste aveugle : dès que deux nœuds se rencontrent, ils échangent tous les bundles qu'ils ne possèdent pas encore en commun.
- **Avantage théorique :** Dans un réseau idéal sans contrainte de mémoire ni de bande passante, Epidemic garantit mathématiquement le délai de livraison minimal (*optimal delay*), car il explore simultanément tous les chemins physiques possibles.
- **Catastrophe pratique :** Dès que le volume de trafic augmente, les files d'attente saturent. Le réseau s'effondre sous l'effet de tempêtes de diffusion (*broadcast storms*) et de destructions massives de paquets par dépassement de buffer (*drop-tail*).

Pour surmonter cette limite, deux philosophies majeures ont émergé :
- **L'arbitrage spatio-temporel et radio (Meshtastic) :** Limiter le rayon de propagation via un `hop_limit` strict, dédupliquer agressivement et introduire une fenêtre de contention inversement proportionnelle à la qualité du signal radio (SNR).
- **Le contingentement strict par quotas (Spray and Wait) :** Borner a priori le nombre maximal $L$ de copies autorisées à circuler dans l'ensemble du réseau, éliminant tout risque de prolifération exponentielle incontrôlée.

---

## 2. Décryptage des Algorithmes

### 2.1. Spray and Wait (Spyropoulos, Psounis, Raghavendra)
Pour pallier la démesure d'Epidemic tout en conservant une grande simplicité, Spray and Wait découpe la vie d'un bundle en deux phases distinctes :

```
             [ Source émettrice : Quota L copies ]
                               |
                               v
                     +-------------------+
                     |   Phase SPRAY     |  (L > 1)
                     +-------------------+
                               |
            +------------------+------------------+
            |                                     |
    (Source Spray)                         (Binary Spray)
  Donne 1 copie par relais,              Donne floor(L/2) copies,
  conserve (L - 1) copies                garde ceil(L/2) copies
            |                                     |
            +------------------+------------------+
                               |
                               v
                     +-------------------+
                     |   Phase WAIT      |  (L == 1)
                     +-------------------+
                               |
              (Relais intermédiaire interdit !)
            Attente passive de la destination finale
```

#### A. Source Spray vs Binary Spray
- **Source Spray :** Seule la source distribue des copies. Dès qu'elle croise un nœud relais qui ne possède pas le bundle, elle lui transmet 1 copie (qui passe immédiatement en phase *Wait* avec $L=1$). La source décrémente son quota local de 1.
- **Binary Spray :** Tout nœud possédant $L > 1$ copies peut répliquer. Lorsqu'il rencontre un nœud sans copie, il lui transfère $\lfloor L / 2 \rfloor$ copies et conserve $\lceil L / 2 \rceil$ copies. Cette distribution binaire est beaucoup plus rapide que le mode source, car l'effort de dissémination est partagé exponentiellement entre porteurs.

#### B. La Phase Wait ($L = 1$)
Dès qu'un porteur ne dispose plus que d'une seule copie ($L = 1$), il bascule en phase **Wait**. Il lui est **strictement interdit** de transmettre le bundle à un autre relais intermédiaire. Il transporte le bundle jusqu'à rencontrer directement l'Endpoint de destination finale (`contact.peer_eid == destination`).

---

### 2.2. Le Flooding Géré de Meshtastic (*Managed Flooding*)
Conçu pour des microcontrôleurs ESP32/nRF52 opérant sur la bande ISM 868/915 MHz en modulation LoRa, Meshtastic applique une inondation hautement optimisée pour la radio bas débit :

1. **Table de déduplication (*Seen Cache*) :** Chaque trame porte un `packet_id` (32 bits). Tout paquet déjà reçu au cours d'une fenêtre glissante est immédiatement détruit à l'ingress.
2. **Ségrégation de canal (*Channel Hash*) :** Le paquet est filtré selon un hash de canal (ex: canal public par défaut vs canal privé chiffré).
3. **Fenêtre de contention pondérée par le SNR (*SNR-based backoff*) :**  
   Lorsqu'un nœud reçoit un paquet à relayer en diffusion radio, il ne réémet pas immédiatement. Il calcule un délai de temporisation :
   $$\text{Backoff}(SNR) = \text{BaseDelay} + \text{Factor} \times \max(0, SNR_{\text{dB}} + 15)$$
   - **Nœud lointain (faible SNR, ex: -10 dB) :** Reçoit une temporisation **courte**. Il retransmet en priorité pour propager le paquet le plus loin possible.
   - **Nœud proche (fort SNR, ex: +10 dB) :** Reçoit une temporisation **longue**.
   - **Annulation par écoute (*Contention Cancel*) :** Si pendant sa temporisation, le nœud proche entend le paquet être retransmis par un pair, il **annule sa propre transmission**. Cela supprime les échos inutiles entre nœuds géographiquement voisins !

---

## 3. Spécification CDDL et Épuration Radicale : Spray & Wait et Meshtastic

Le fichier [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl) intègre les primitives requises sous le bloc expérimental type `200` :

```cddl
; Bloc expérimental BPv7 modulaire et agnostique (Type 200)
mesh-routing-data = {
    ? 1 => legacy-bridge-id: (bytes / uint), ; Empreinte externe optionnelle (passerelle LoRa)
    ? 2 => replication-control,              ; Primitives de contingentement et quotas
    ...
}

; Dimension Réplication (utilisée par Spray & Wait, MaxProp, etc.)
replication-control = {
    1 => quota: uint,                        ; Quota L de copies attribuées
    ? 2 => mode: &(mode-source: 1, mode-binary: 2), ; Distribution unitaire ou binaire
    ? 3 => phase: &(phase-disseminate: 1, phase-wait: 2), ; Phase active
    ? 4 => generation: uint                  ; Génération / niveau de réplication
}
```

### 3.1. Réconciliation Architecturale : Hop Count Block (Type 10) et Bundle ID Universel

Deux simplifications majeures ont été dégagées lors de notre modélisation :

1. **La limite de saut Meshtastic est 100 % isomorphe au Hop Count Block (Type 10) :**  
   Meshtastic utilise `hop_start` (la valeur initiale) et `hop_limit` (décrémenté à chaque saut). Dans la RFC 9171, le **Hop Count Block (Type 10)** utilise `hop_limit` et `hop_count`.  
   L'équivalence est absolue : $\text{hop\_start} = \text{hop\_limit}_{\text{Type 10}}$ et le nombre de sauts restants sous Meshtastic vaut $\text{hop\_limit} - \text{hop\_count}$.  
   En réutilisant le bloc standard Type 10, **tout routeur DTN conventionnel** (même dépourvu de la logique LoRa Meshtastic) coupe net la propagation du paquet s'il dépasse sa limite !

2. **L'inutilité des `packet-id` et `message-id` :**  
   Alors que Meshtastic et Spray & Wait définissent chacun un identifiant de paquet ou de message pour leur table anti-doublon ou leurs *Summary Vectors*, le **Bundle ID canonique** `(source_eid, creation_time, sequence_number)` de la RFC 9171 Section 4.2.2 remplit nativement et universellement cet office. Aucun identifiant ad-hoc n'a besoin d'être transporté dans le bloc d'extension en DTN natif.

### 3.2. Pourquoi le `channel_id` a été supprimé : Le canal radio n'est pas une métadonnée BPv7

Une réflexion architecturale poussée nous a conduits à éliminer tout champ de canal radio (`wireless-channel` / `channel_id`) du bloc d'extension filaire :
- **Violation du découpage en couches :** Le Bundle Protocol est un réseau superposé (*overlay*). Un canal LoRa ou une fréquence radio sont des propriétés de couche 1 / 2 (PHY / Liaison). Si un bundle traverse une liaison satellite ou un tunnel TCPCL entre deux villes, un identifiant de canal radio local n'a plus aucun sens.
- **Filtrage applicatif par EID (Whitelist) :** Dans Meshtastic, la ségrégation de canal sert à filtrer les flux que le nœud ne souhaite pas relayer. En DTN, cela s'exprime de manière infiniment plus élégante et universelle par une **whitelist de motifs d'EID de destination** (`input.node.allowed_destinations`, ex: `dtn://channels/emergency/*`) ou directement au niveau de l'adaptateur CLA d'entrée.

### 3.3. Le Constat Majeur : Meshtastic opère en pur BPv7 standard !

Ce raisonnement aboutit à une conclusion remarquable : **l'inondation gérée de Meshtastic ne nécessite aucun bloc d'extension propriétaire sur les ondes !**
- Le contrôle du rayon de propagation repose sur le standard **Hop Count Block (Type 10)**.
- La déduplication repose sur le standard **Bundle ID canonique BPv7**.
- La ségrégation de flux repose sur les **EIDs standardisés**.
- Le calcul de temporisation de contention ($Backoff(SNR)$) et l'annulation par écoute sont des **décisions d'orchestration purement locales**, confiées au moteur OPA via la télémétrie d'entrée (`input.ingress.snr_db`) et l'état interne (`input.node.cancelled_rebroadcasts`).

---

## 4. Implémentation Déclarative avec OPA (Rego)

Toutes les règles sont implémentées dans [policies/flood/](./policies/flood/).

### 4.1. Fonctions d'Aide Mathématiques ([helpers.rego](./policies/flood/helpers.rego))

```rego
package dtn.flood.helpers

# Division binaire de quota pour Spray & Wait
calculate_binary_spray(quota) := result if {
    quota >= 2
    to_send := floor(quota / 2)
    to_keep := quota - to_send
    result := {
        "send_quota": to_send,
        "keep_quota": to_keep,
        "new_local_phase": phase_for_quota(to_keep),
        "transmitted_phase": phase_for_quota(to_send)
    }
}

# Calcul de contention Meshtastic
calculate_meshtastic_backoff(snr_db) := delay_ms if {
    clamped_snr := max([snr_db + 15, 0])
    delay_ms := constants.meshtastic_base_backoff_ms + round(clamped_snr * constants.meshtastic_snr_factor_ms)
}
```

### 4.2. Ingress Policy ([ingress.rego](./policies/flood/ingress.rego))

1. **Déduplication universelle :** Rejet immédiat si l'identifiant du bundle a déjà été vu.
2. **Ingress Spray & Wait :** Enregistre le bundle et initialise la phase (`SPRAY` si $L > 1$, `WAIT` si $L = 1$).
3. **Ingress Meshtastic :**
   - Vérifie la conformité du `channel_hash` avec celui du nœud local.
   - Calcule le délai de temporisation de rediffusion selon le SNR de réception et l'ordonne via une mutation CBOR.

### 4.3. Contact Policy ([contact.rego](./policies/flood/contact.rego))

La prise de décision lors d'une opportunité de liaison CLA traduit fidèlement les règles théoriques :

```rego
# 1. Contact direct avec la destination : livraison immédiate sans condition
decision := {
    "action": "FORWARD_DIRECT",
    "reason": "Peer is the destination endpoint",
    "mutations": []
} if {
    input.contact.peer_eid == input.bundle.primary.destination
}

# 2. Interdiction formelle de relayer un bundle en phase WAIT à un intermédiaire
decision := {
    "action": "SKIP",
    "reason": "Spray & Wait bundle is in WAIT phase (L=1): awaiting direct destination contact only",
    "mutations": []
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    block := helpers.get_spray_block(input.bundle)
    not helpers.peer_already_holds_bundle(input.contact, block.payload.message_id)
    block.payload.replication_quota <= 1
}

# 3. Réplication en mode Binary Spray
decision := {
    "action": "FORWARD_REPLICATE",
    "reason": sprintf("Binary spray: splitting quota L=%v", [block.payload.replication_quota]),
    "mutations": [{
        "block_type": constants.block_type_mesh_routing,
        "operation": "MUTATE_SPRAY_QUOTA",
        "local_quota": split.keep_quota,
        "local_phase": split.new_local_phase,
        "transmitted_quota": split.send_quota,
        "transmitted_phase": split.transmitted_phase
    }]
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    block := helpers.get_spray_block(input.bundle)
    not helpers.peer_already_holds_bundle(input.contact, block.payload.message_id)
    block.payload.replication_quota >= 2
    block.payload.spray_mode == constants.spray_mode_binary
    split := helpers.calculate_binary_spray(block.payload.replication_quota)
}

# 4. Annulation Meshtastic si entendu pendant le backoff
decision := {
    "action": "SKIP",
    "reason": "Meshtastic rebroadcast cancelled: packet heard from another peer during backoff",
    "mutations": []
} if {
    block := helpers.get_meshtastic_block(input.bundle)
    block.payload.packet_id in object.get(input.node, "cancelled_rebroadcasts", [])
}
```

---

## 5. Validation par les Tests Unitaires OPA (44/44 PASS)

La suite de tests unitaires dédiée ([flood_test.rego](./policies/flood/flood_test.rego)) valide 17 scénarios critiques, portant le total global du dépôt à **44 tests validés avec succès** :

```bash
opa test ./policies -v
```

```text
./policies/flood/flood_test.rego:
data.dtn.flood_test.test_flood_local_delivery: PASS (602µs)
data.dtn.flood_test.test_flood_duplicate_suppression: PASS (1.66ms)
data.dtn.flood_test.test_spray_ingress_spray_phase: PASS (1.82ms)
data.dtn.flood_test.test_spray_ingress_wait_phase: PASS (1.53ms)
data.dtn.flood_test.test_spray_contact_direct_destination: PASS (504µs)
data.dtn.flood_test.test_spray_contact_skip_peer_already_holds: PASS (1.02ms)
data.dtn.flood_test.test_spray_contact_binary_split_even: PASS (3.27ms)
data.dtn.flood_test.test_spray_contact_binary_split_to_wait: PASS (2.40ms)
data.dtn.flood_test.test_spray_contact_source_spray: PASS (1.80ms)
data.dtn.flood_test.test_spray_contact_wait_phase_skip_relay: PASS (1.26ms)
data.dtn.flood_test.test_meshtastic_ingress_channel_match_and_backoff: PASS (3.76ms)
data.dtn.flood_test.test_meshtastic_ingress_channel_mismatch: PASS (1.45ms)
data.dtn.flood_test.test_meshtastic_contact_cancelled_during_backoff: PASS (766µs)
data.dtn.flood_test.test_meshtastic_contact_broadcast_success: PASS (586µs)
data.dtn.flood_test.test_meshtastic_ingress_hop_limit_reached: PASS (1.67ms)
data.dtn.flood_test.test_flood_generic_cddl_replication: PASS (1.64ms)
data.dtn.flood_test.test_flood_generic_cddl_wireless: PASS (3.48ms)
--------------------------------------------------------------------------------
Total global : 44/44 tests PASS
(14 fondations + 13 APRS/Trajectoire + 17 Inondation/Quotas/Contention)
```

---

## 6. Synthèse Comparative : Quel Protocole pour Quel Réseau ?

| Caractéristique | Epidemic Routing | Meshtastic Managed Flooding | Spray and Wait |
| :--- | :--- | :--- | :--- |
| **Nombre maximal de copies** | $N$ (Tous les nœuds du réseau) | Non borné (limité par le TTL radio) | Borne stricte $L$ fixée à l'émission |
| **Consommation mémoire** | Catastrophique sous charge | Modérée (table des ID récents) | Faible et prédictible |
| **Consommation spectrale radio** | Maximale (tempêtes de paquets) | Optimisée par temporisation SNR | Faible ($L-1$ transmissions intermédiaires) |
| **Idéal pour** | Réseaux ultra-clairsemés sans congestion | Réseaux LoRa locaux / citoyens | Flottes véhiculaires, drones, réseaux de secours |

Dans le prochain article (**Article 3**), nous aborderons la famille des **protocoles opportunistes probabilistes** avec **PRoPHET ([RFC 6693](https://www.rfc-editor.org/rfc/rfc6693.html))** : calcul dynamique des probabilités de rencontre, vieillissement (*aging*) et transitivité.

---

👉 **Article suivant :** [Article 3 — Routage Opportuniste et Historique des Rencontres : PRoPHET (RFC 6693) sous Open Policy Agent](./article-3-prophet.md)
