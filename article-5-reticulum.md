# Article 5 — Routage Hybride, Vecteur de Distance et Adressage Cryptographique : Reticulum (RNS) transposé en DTN

> **Série :** *Transposition d'algorithmes de routage mesh & opportunistes vers DTN (BPv7)*  
> **Articles précédents :**  
> - [Article 0 — Les Fondations du Routage DTN avec Open Policy Agent](./article-0-intro.md)  
> - [Article 1 — Transposer le Digipeating APRS (AX.25 WIDE n-N) en DTN (BPv7)](./article-1-aprs.md)  
> - [Article 2 — Dompter l'Inondation en DTN : D'Epidemic à Spray and Wait et au Flooding Géré de Meshtastic](./article-2-flood.md)  
> - [Article 3 — Routage Opportuniste et Historique des Rencontres : PRoPHET (RFC 6693) sous Open Policy Agent](./article-3-prophet.md)  
> - [Article 4 — Routage Probabiliste et Gestion de Mémoire sous Contrainte : MaxProp et ses Optimisations Théoriques (HP-MaxProp)](./article-4-maxprop.md)  
> **Article suivant :**  
> - [Article 6 — Réseaux Maillés Proactifs et Hybridation MANET-DTN : AREDN, Babel (RFC 8966) et l'Architecture HYMAD sous Open Policy Agent](./article-6-babel-aredn.md)  
> **Spécifications CDDL :** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl), [prophet.cddl](./prophet.cddl) & [reticulum.cddl](./reticulum.cddl)  
> **Code des politiques :** [policies/reticulum/](./policies/reticulum/) ([ingress.rego](./policies/reticulum/ingress.rego), [contact.rego](./policies/reticulum/contact.rego), [storage.rego](./policies/reticulum/storage.rego), [helpers.rego](./policies/reticulum/helpers.rego), [constants.rego](./policies/reticulum/constants.rego), [reticulum_test.rego](./policies/reticulum/reticulum_test.rego))

---

## 1. L'Impératif Zéro-IP et l'Identité Auto-Souveraine

Jusqu'ici, notre exploration des réseaux maillés et tolérants aux délais a couvert :
1. Le routage à la source et la consommation d'alias d'acheminement sous contrainte radio ([APRS AX.25](./article-1-aprs.md)).
2. L'inondation régulée par quotas stricts ou par temporisation physique de canal ([Spray and Wait & Meshtastic](./article-2-flood.md)).
3. Le routage opportuniste guidé par l'apprentissage statistique des contacts humains ([PRoPHET RFC 6693](./article-3-prophet.md)).
4. L'ordonnancement de transmission et l'éviction de buffer fondés sur la théorie de l'information ([MaxProp](./article-4-maxprop.md)).

Cependant, tous ces protocoles s'appuient soit sur des identifiants administratifs statiques (indicatifs radioamateurs en APRS, adresses MAC/numéros de nœuds en Meshtastic, URI textuels en PRoPHET), soit sur une inondation globale de chaque message.

Que se passe-t-il lorsque l'on souhaite bâtir un réseau **totalement décentralisé, sans coordination centrale, sans adresses IP, sans serveurs DNS, tout en garantissant un chiffrement de bout en bout et un routage unicast précis à l'échelle planétaire** ?

C'est précisément l'objectif de **Reticulum Network Stack (RNS)**, conçu par Mark Qvist. Reticulum part d'un constat radical : la pile TCP/IP traditionnelle impose des hiérarchies d'adresses (subnets, préfixes BGP, passerelles par défaut) inadaptées aux réseaux ad-hoc, aux liaisons radio à très faible débit (LoRa, HF, VHF) et aux environnements hostiles où l'anonymat et la souveraineté cryptographique sont primordiaux.

---

## 2. Les Piliers Architecturaux de Reticulum

```
+-----------------------------------------------------------------------------+
|                           RETICULUM NETWORK STACK                           |
+-----------------------------------------------------------------------------+
|  1. Adressage Cryptographique Auto-Souverain                                |
|     -> Hash SHA-256 tronqué à 16 octets (128 bits) de la clé publique       |
+-----------------------------------------------------------------------------+
|  2. Découverte de Chemin par Annonces Signées (Announces)                   |
|     -> Clé publique + Sel aléatoire + Compteur de sauts + Signature Ed25519 |
+-----------------------------------------------------------------------------+
|  3. Table de Routage au Prochain Saut (Next-Hop Distance-Vector)            |
|     -> L'annonce la plus courte met à jour le voisin relais désigné         |
+-----------------------------------------------------------------------------+
|  4. Preuves Cryptographiques de Livraison (Proofs)                          |
|     -> Signature de reçu prouvant mathématiquement la réception du bundle   |
+-----------------------------------------------------------------------------+
```

### 2.1. L'Adressage par Hash Cryptographique (16 octets / 128 bits)
Dans Reticulum, une destination n'est ni un nom de domaine, ni une adresse IP. C'est le **hash SHA-256 tronqué aux 16 premiers octets (128 bits)** de la clé publique de la destination (ou d'un couple clé publique + aspect applicatif).
- **Auto-authentification :** N'importe quel nœud peut générer une paire de clés asymétriques (Curve25519 pour ECDH, Ed25519 pour la signature) localement, sans demander l'autorisation à une autorité de certification.
- **Transposition en DTN (BPv7) :** L'EID de destination prend la forme naturelle :
  $$\text{dtn://rns/} \langle 16\text{-byte-hex-hash} \rangle /$$
  Exemple : `dtn://rns/a1b2c3d4e5f60718293a4b5c6d7e8f90/`. L'EID s'intègre directement dans le Primary Block standard de la [RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html).

### 2.2. La Découverte de Chemin : Les Annonces Signées (*Announces*)
Pour qu'un nœud puisse recevoir des messages unicast, il diffuse une **Annonce** sur le réseau.
Chaque annonce transporte :
1. Le hash de la destination (16 octets).
2. La clé publique complète de la destination (32 octets).
3. Un sel aléatoire de 10 octets (pour éviter les attaques par rejeu).
4. Un compteur de sauts initialisé à `0`.
5. Une signature cryptographique Ed25519 (64 octets) couvrant l'ensemble.
6. Optionnellement, des données applicatives chiffrées ou une clé à cliquet éphémère (*ratchet*) pour le *Forward Secrecy*.

À mesure que l'annonce se propage de proche en proche :
- Chaque nœud intermédiaire qui la relaie incrémente le compteur de sauts.
- Il enregistre dans sa **table de routage locale** :
  $$\text{Destination Hash} \implies (\text{Next Hop} = \text{Pair Émetteur Immédiat}, \text{Distance} = \text{Sauts} + 1, \text{Expiration} = \text{Now} + \text{TTL})$$
- Si une annonce ultérieure parvient au nœud avec un nombre de sauts supérieur ou égal, elle est ignorée. Si elle propose un chemin **strictement plus court**, la route est mise à jour.

### 2.3. L'Acheminement Unicast vers le Prochain Saut (*Next-Hop Forwarding*)
Une fois les tables de routage alimentées par les annonces :
- Les bundles de données vers cette destination ne sont **plus inondés**.
- Le nœud consulte sa table de routage, identifie le voisin immédiat (`next_hop_eid`), et transmet le paquet exclusivement à ce pair.
- Chaque saut successif répète cette opération jusqu'à la destination finale.

### 2.4. Découverte Réactive : Les Requêtes de Chemin (*Path Requests*)
Si un nœud doit expédier un bundle vers une destination dont il ne possède aucune annonce en cache, il émet un message de contrôle `Path Request`.
Tout nœud intermédiaire disposant d'un chemin valide vers cette destination peut répliquer par une `Path Response` contenant la dernière annonce signée valide en guise de preuve.

---

## 3. Le Coup de Maître : Zéro Bloc Filaire Spécifique pour les Données en DTN

L'un des résultats les plus élégants de notre modélisation architecturale concerne le format filaire : **tout comme Meshtastic dans l'[Article 2](./article-2-flood.md), Reticulum ne requiert aucun bloc d'extension propriétaire sur le câble pour acheminer les bundles de données en DTN.**

Examinons pourquoi :

| Besoin Reticulum | Implémentation Native RNS | Équivalent Standard BPv7 ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html)) | Bloc Requis sur le Câble ? |
| :--- | :--- | :--- | :--- |
| **Identifiant Destinataire** | Hash tronqué 16 octets dans l'en-tête de paquet | Destination EID dans le Primary Block (`dtn://rns/<hash>/`) | **Standard RFC 9171** (Primary Block) |
| **Prévention des boucles** | Compteur de sauts (Hop limit) décrémenté | **Hop Count Block (Type 10)** (`hop_limit`, `hop_count`) | **Standard RFC 9171** (Type 10) |
| **Déduplication** | Hash de paquet | **Bundle ID Canonique** `(source, time, sequence)` | **Standard RFC 9171** (Section 4.2.2) |
| **Évitement de renvoi immédiat** | Filtrage d'interface | **Previous Node Insertion Block (Type 6)** | **Standard RFC 9171** (Type 6) |
| **Table de Routage Next-Hop** | Table en RAM du nœud | Injection dans le contexte OPA (`input.node.routing_table`) | **Zéro octet sur le câble** (Local OPA) |

Les paquets de données Reticulum bénéficient donc d'une interopérabilité totale avec n'importe quel routeur DTN standard respectant la RFC 9171.

---

## 4. Spécification des Messages de Signalisation : `reticulum.cddl`

Si les paquets de données voyagent sous la forme de bundles ordinaires, la signalisation inter-nœuds (Annonces, Requêtes et Preuves) nécessite en revanche un format d'échange formalisé.

Dans notre architecture, ces messages sont encapsulés dans le **payload d'un bundle administratif** (ex: adressé à `dtn://rns/announce` ou au pair distant via la CLA).

Le fichier **[reticulum.cddl](./reticulum.cddl)** spécifie ces structures en CBOR :

```cddl
; Message de contrôle Reticulum transporté dans le payload d'un bundle administratif
reticulum-control-bundle = {
    1 => message-type: reticulum-message-type,
    2 => destination-hash: bytes .size 16,  ; Hash SHA-256 tronqué à 16 octets
    3 => timestamp-ms: uint,                ; Horloge DTN de création
    4 => payload: reticulum-payload         ; Charge utile selon le type
}

reticulum-message-type = &(
    msg-announce: 1,      ; Annonce de destination et découverte de chemin
    msg-path-request: 2,  ; Requête explicite de chemin vers une destination
    msg-path-response: 3, ; Réponse de chemin (chemin connu par un tiers)
    msg-proof: 4          ; Preuve de réception / accusé cryptographique
)

; Structure d'une Annonce signée
announce-payload = {
    1 => public-key: bytes .size 32,        ; Clé publique Ed25519 ou Curve25519
    2 => announce-hops: uint,               ; Compteur de sauts d'annonce (0 à l'origine)
    3 => random-salt: bytes .size 10,       ; Sel aléatoire (protection anti-rejeu)
    4 => signature: bytes .size 64,         ; Signature Ed25519 par la clé de destination
    ? 5 => app-data: bytes,                 ; Métadonnées applicatives chiffrées ou claires
    ? 6 => ratchet: bytes .size 32          ; Clé éphémère (Forward Secrecy)
}

; Preuve de réception cryptographique (Proof)
proof-payload = {
    1 => bundle-id-hash: bytes .size 32,    ; Hash de l'identifiant du bundle acquitté
    2 => signature: bytes .size 64          ; Signature par la clé privée du destinataire
}
```

---

## 5. Le Store-Carry-and-Forward : La Revanche du DTN sur Reticulum Natif

Dans le logiciel Reticulum d'origine (sur microcontrôleur ou Raspberry Pi) :
- Si un nœud tente d'expédier un paquet vers une destination pour laquelle il ne possède **aucune entrée de table de routage**, il déclenche une *Path Request*.
- Cependant, si aucune réponse ne revient dans un délai court ou si le lien physique immédiat est interrompu, le paquet est tout simplement **abandonné (*drop*)** car Reticulum n'a pas été conçu initialement comme un système de garde à long terme (*custody storage*).

C'est ici que l'hybridation avec le **Bundle Protocol v7** démontre sa supériorité opérationnelle :

```
             Flux de Données Reticulum en Environnement Disrompu
             ====================================================

      Émission du Bundle vers dtn://rns/<hash>/
                         |
                         v
             Route connue en table ?
            /                       \
        [ OUI ]                   [ NON ]
           |                         |
     Forward Next-Hop          Garde DTN active (Store-Carry-and-Forward)
  (Acheminement Unicast)             |
                               Bundle conservé en mémoire locale (Buffer)
                                     +
                               Déclenchement optionnel d'un Path Request
                                     |
                               Contact ultérieur avec un porteur d'Annonce ?
                                     |
                               [ Annonce Reçue ]
                                     |
                               Mise à jour de la table de routage
                                     |
                               Forward différé vers le nouveau Next-Hop !
```

Grâce aux primitives DTN, **aucun paquet n'est perdu lors d'une partition réseau**. Le bundle patiente en mémoire tampon (`action: "SKIP"` lors des contacts non pertinents, `action: "RETAIN_AND_REQUEST_PATH"` lors des audits de stockage), jusqu'à ce qu'un contact physique apporte l'annonce attendue.

---

## 6. Modélisation Déclarative sous Open Policy Agent (OPA)

Le répertoire **[policies/reticulum/](./policies/reticulum/)** implémente l'ensemble des règles de décision régissant le comportement d'un routeur Reticulum/DTN.

### 6.1. Ingress : Ingestion d'Annonces et Mise à Jour de Table ([ingress.rego](./policies/reticulum/ingress.rego))

À l'entrée, la politique distingue les paquets de données des annonces de chemin :

```rego
# Règle Ingress 6 : Annonce Reticulum avec découverte de chemin plus court
decision := {
    "action": "ACCEPT_ANNOUNCE",
    "reason": sprintf("Reticulum announce accepted: discovered next-hop path to %v via %v (%v hops)", [
        announced_dest,
        peer_eid,
        hops + 1
    ]),
    "mutations": [
        {
            "operation": "UPDATE_ROUTING_TABLE",
            "destination_hash": announced_dest,
            "next_hop": peer_eid,
            "hops": hops + 1,
            "expires_at_ms": input.current_dtn_time_ms + constants.default_path_ttl_ms
        },
        {
            "block_type": base_constants.block_type_hop_count,
            "operation": "SET_FIELD",
            "field": "hop_count",
            "value": hops + 1
        }
    ]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    helpers.is_announce(input.bundle)
    announced_dest := input.bundle.primary.source
    peer_eid := object.get(input.ingress, "peer_eid", announced_dest)
    hcb := base_helpers.get_hop_count_block(input.bundle)
    hops := hcb.hop_count
    existing := helpers.get_route_entry(announced_dest, object.get(input.node, "routing_table", {}))
    helpers.should_update_path(existing, hops + 1, input.current_dtn_time_ms)
}
```

La fonction d'aide [helpers.should_update_path](./policies/reticulum/helpers.rego#L60-L73) formalise les conditions du vecteur de distance :
1. Aucun chemin n'était connu pour cette destination.
2. Le chemin enregistré a expiré (`current_time > expires_at_ms`).
3. L'annonce entrante propose un chemin strictement plus court (`new_hops < existing.hops`).

### 6.2. Contact : Forwarding Unicast au Prochain Saut Désigné ([contact.rego](./policies/reticulum/contact.rego))

Lorsqu'une opportunité de transmission se présente avec un pair :
- S'il s'agit d'une annonce et que le lien est en broadcast : rediffusion (`FORWARD_BROADCAST`).
- S'il s'agit d'un bundle de données et que le pair connecté est le prochain saut enregistré : transmission immédiate (`FORWARD_NEXT_HOP`).
- Si le pair connecté n'est pas le prochain saut, ou si la route est inconnue : rétention en stockage (`SKIP`).

```rego
# Règle Contact 5 : Acheminement vers le Prochain Saut désigné
decision := {
    "action": "FORWARD_NEXT_HOP",
    "reason": sprintf("Routing table match: forwarding to next-hop %v (%v hops to destination)", [
        route.next_hop_eid,
        route.hops
    ]),
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_announce(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    route != null
    helpers.is_route_valid(route, input.current_dtn_time_ms)
    input.contact.peer_eid == route.next_hop_eid
}
```

### 6.3. Storage : Déclenchement de Path Requests en Arrière-Plan ([storage.rego](./policies/reticulum/storage.rego))

Lors de la revue périodique des mémoires tampons :
- Les bundles orphelins (sans route valide en table) déclenchent une mutation `TRIGGER_PATH_REQUEST` pour réveiller la découverte réactive si le nœud l'autorise.

```rego
decision := {
    "action": "RETAIN_AND_REQUEST_PATH",
    "reason": "Bundle destination route unknown or expired: trigger Reticulum path discovery",
    "mutations": [{
        "operation": "TRIGGER_PATH_REQUEST",
        "destination_hash": input.bundle.primary.destination
    }]
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_announce(input.bundle)
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    not is_valid_route(route, input.current_dtn_time_ms)
    object.get(input.node, "enable_path_requests", false) == true
}
```

---

## 7. Validation par les Tests Unitaires OPA (92/92 PASS)

L'implémentation a été validée par 16 tests unitaires complets dans [reticulum_test.rego](./policies/reticulum/reticulum_test.rego), portant le total de la suite de tests à **92 tests réussis avec un taux de réussite de 100%**.

```bash
opa test ./policies -v
```

```text
policies/aprs/aprs_test.rego:
  13 tests validés (digipeating AX.25, règles Dire Wolf 6.1b, 6.3c, trapping §10)
policies/contact_test.rego:
  5 tests validés (fondations contact CLA, split-horizon, lifetime)
policies/flood/flood_test.rego:
  17 tests validés (Spray & Wait binaire/source, Meshtastic SNR backoff et contention)
policies/ingress_test.rego:
  6 tests validés (fondations ingress, Hop Count Type 10, blacklist sources)
policies/maxprop/maxprop_test.rego:
  16 tests validés (coût logarithmique, pénalité de saut fluide, 2-hop gossip, cleared list)
policies/prophet/prophet_test.rego:
  16 tests validés (équations mathématiques, RIB handshake, éviction sélective)
policies/reticulum/reticulum_test.rego:
  data.dtn.reticulum_test.test_reticulum_ingress_local_delivery_by_eid: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_local_delivery_by_hash: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_blacklisted_source: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_expired: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_hop_limit_reached: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_announce_new_route: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_announce_shorter_path: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_announce_longer_path_ignored: PASS
  data.dtn.reticulum_test.test_reticulum_contact_direct_destination: PASS
  data.dtn.reticulum_test.test_reticulum_contact_announce_broadcast: PASS
  data.dtn.reticulum_test.test_reticulum_contact_forward_matching_next_hop: PASS
  data.dtn.reticulum_test.test_reticulum_contact_skip_non_next_hop_peer: PASS
  data.dtn.reticulum_test.test_reticulum_contact_skip_unknown_destination: PASS
  data.dtn.reticulum_test.test_reticulum_contact_skip_expired_route: PASS
  data.dtn.reticulum_test.test_reticulum_storage_drop_expired: PASS
  data.dtn.reticulum_test.test_reticulum_storage_trigger_path_request: PASS
policies/storage_test.rego:
  3 tests validés (gestion du Bundle Age Block Type 7)
--------------------------------------------------------------------------------
PASS: 92/92
```

---

## 8. Grande Synthèse Comparative des 4 Algorithmes

Voici la cartographie transversale comparant l'ensemble des protocoles étudiés et implémentés au fil de notre série :

| Critère | APRS AX.25 ([Article 1](./article-1-aprs.md)) | Meshtastic ([Article 2](./article-2-flood.md)) | PRoPHET RFC 6693 ([Article 3](./article-3-prophet.md)) | Reticulum RNS ([Article 5](./article-5-reticulum.md)) |
| :--- | :--- | :--- | :--- | :--- |
| **Paradigme de Routage** | Routage à la source & alias génériques | Inondation gérée (*Managed Flooding*) | Routage opportuniste probabiliste | Vecteur de distance réactif / proactif |
| **Format d'Adressage** | Indicatifs radioamateurs (`NOCALL-1`) | NodeNum 32 bits (`!a1b2c3d4`) | EID URI textuels (`dtn://dest/`) | Hashes cryptographiques 16 octets (`dtn://rns/<hash>/`) |
| **Blocs Filaire DTN Requis** | Extension Bloc Type 200 (`trajectory_control`) | **Aucun** (Pur BPv7 standard : Type 10) | Optionnel Type 200 (`opportunistic_threshold`) | **Aucun** (Pur BPv7 standard : Type 10) |
| **Messages de Signalisation** | Aucun (diffusion aveugle) | Aucun (canaux pré-partagés) | Échanges bilatéraux RIB & SV ([prophet.cddl](./prophet.cddl)) | Annonces signées & Requêtes de chemin ([reticulum.cddl](./reticulum.cddl)) |
| **Acheminement des Données** | Multidiffusion broadcast | Diffusion générale avec SNR backoff | Recommmandation opportuniste aux pairs favorables | **Unicast strict** vers le prochain saut désigné |
| **Gestion des Boucles** | Consommation d'alias & Split Horizon Type 6 | Déduplication par Bundle ID & Hop Count Type 10 | Décroissance transitive & Hop Count Type 10 | Métrique de sauts stricts & Hop Count Type 10 |
| **Comportement hors partition** | Abandon de paquet si non relayé | Abandon si aucun relais n'écoute | Porté en mémoire jusqu'au contact favorable | **Garde DTN active** (Store-Carry-and-Forward) |
| **Sécurité Native** | Nulle (trames AX.25 en clair) | Chiffrement symétrique AES-256 de canal | Nulle par défaut (déléguée au BPSec) | **Clés asymétriques Ed25519 & Curve25519, PFS** |

---

## 9. Conclusion et Perspectives

La transposition de Reticulum vers le Bundle Protocol v7 parachève la démonstration de la modularité de DTN :
1. **L'universalité de BPv7 :** Sans modifier la norme de transport, BPv7 peut accueillir aussi bien du routage à la source, de l'inondation aveugle, du calcul probabiliste que du vecteur de distance cryptographique.
2. **L'élégance de la séparation des plans :** Le moteur filaire reste minimaliste et robuste ; la complexité décisionnelle est entièrement déportée dans des politiques déclaratives OPA vérifiables et auditables.
3. **La résilience accrue :** Reticulum apporte à DTN son adressage cryptographique zero-trust ; DTN offre à Reticulum la persistance indestructible du *Store-Carry-and-Forward*.

Dans le prochain article ([Article 6](./article-6-babel-aredn.md)), nous nous intéresserons aux protocoles d'infrastructure proactifs basés sur l'état des liens avec **AREDN (Babel / RFC 8966)** et à l'architecture hybride MANET-DTN **HYMAD** !

---

👉 **Article suivant :** [Article 6 — Réseaux Maillés Proactifs et Hybridation MANET-DTN : AREDN, Babel (RFC 8966) et l'Architecture HYMAD sous Open Policy Agent](./article-6-babel-aredn.md)
