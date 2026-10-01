# Article 0 — Les Fondations du Routage DTN avec Open Policy Agent : Cycle de Vie, Hop Limit et Expiration

> **Série :** *Transposition d'algorithmes de routage mesh & opportunistes vers DTN (BPv7)*  
> **Auteur :** Recherche & Ingénierie DTN Mesh  
> **Code associé :** [policies/](./policies) ([ingress.rego](./policies/ingress.rego), [storage.rego](./policies/storage.rego), [contact.rego](./policies/contact.rego), [helpers.rego](./policies/helpers.rego), [dtn_constants.rego](./policies/dtn_constants.rego))

> ℹ️ **Transparence Éditoriale (Conformité EU AI Act) :** Cet article a été rédigé avec l'assistance d'une IA sous la direction éditoriale et la structuration d'un auteur humain, qui en assure la relecture, la vérification technique et la responsabilité du contenu (relecture en cours).

---

## 1. Introduction : Pourquoi piloter un routeur DTN avec OPA ?

Le **Bundle Protocol version 7 ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html))** est conçu pour opérer au-dessus de réseaux hétérogènes, intermittents et soumis à de fortes latences (liaisons spatiales, réseaux maillés tactiques, capteurs LoRa, liaisons radioamateurs AX.25). Contrairement à la pile IP classique où le routage est délégué à des tables de commutation statiques ou à des protocoles dynamiques en temps réel (BGP, OSPF), le DTN repose sur le paradigme **Store-Carry-and-Forward** :

1. Un nœud reçoit un bundle.
2. Il le valide et l'enregistre dans son stockage persistant (*Bundle Store*).
3. Il attend une opportunité de contact (parfois plusieurs heures ou jours).
4. Il sélectionne les bundles éligibles et les transmet à un pair via un adaptateur de couche de convergence (*Convergence Layer Adapter* - CLA).

Dans la majorité des implémentations historiques (ION, IBR-DTN, uD3TN), les règles de routage (Epidemic, PRoPHET, CGR) sont codées en dur en C/C++ ou en Python, étroitement couplées à la boucle d'événements du démon de routage.

**Notre thèse d'architecture :**  
En déléguant la prise de décision à un moteur de politiques déclaratif comme **Open Policy Agent (OPA)** via le langage **Rego**, on sépare strictement :
- **Le plan de données (*Data Plane*) :** Réception CBOR, validation cryptographique BPSec ([RFC 9172](https://www.rfc-editor.org/rfc/rfc9172.html)), persistance disque et transmission CLA.
- **Le plan de contrôle (*Control/Decision Plane*) :** Application des règles de rétention, calcul des quotas de réplication, filtrage des contacts, détection des boucles et drop des bundles invalides.

Avant d'aborder des algorithmes complexes comme Spray and Wait, PRoPHET ou le digipeating APRS, ce premier article pose les **fondations élémentaires et non négociables** de tout nœud DTN : **la destruction des bundles dont le nombre de sauts (*hop-count*) est dépassé et ceux dont la durée de vie (*lifetime*) a expiré.**

---

## 2. Les Règles Fondamentales de la RFC 9171

### 2.1. Époque DTN vs Époque Unix
Une source fréquente de bugs en DTN réside dans la gestion du temps. L'époque standard du Bundle Protocol (DTN Time) est fixée au **1er janvier 2000 à 00:00:00 UTC**, et non au 1er janvier 1970 (époque Unix). Le décalage exact est de **946 684 800 secondes** (soit `946 684 800 000 ms`).

### 2.2. Expiration de la Lifetime : Le piège des nœuds sans horloge temps réel (RTC)
La RFC 9171 gère deux situations d'horodatage :
1. **Nœud avec horloge synchronisée (`creation_timestamp.time > 0`) :**  
   L'expiration survient dès que :  
   $$\text{CurrentDTNTime} \ge \text{creation\_timestamp.time} + \text{lifetime}$$
2. **Nœud sans horloge synchronisée (`creation_timestamp.time == 0`) :**  
   Très fréquent sur les nœuds IoT / LoRa ou les microcontrôleurs redémarrés sans GPS ni NTP. Dans ce cas, la RFC 9171 **impose** la présence du **Bundle Age Block (Type 7)**. L'âge relatif du bundle $\text{bundle\_age}$ est incrémenté en millisecondes au fil du trajet et du stockage. L'expiration survient dès que :  
   $$\text{bundle\_age} \ge \text{lifetime}$$

### 2.3. Hop Count Block (Type 10) et Prévention des Tempêtes
Le **Hop Count Block (Type 10)** contient deux entiers non signés : `hop_limit` et `hop_count`.
La section 4.3.3 de la RFC 9171 spécifie deux moments critiques :
- **À la réception (*Ingress*) :** Le nœud **DOIT** incrémenter le `hop_count` de 1. Si $\text{hop\_count} \ge \text{hop\_limit}$, le bundle **DOIT** être détruit (sauf s'il est destiné au nœud local).
- **Avant l'émission (*Forwarding*) :** Si $\text{hop\_count} \ge \text{hop\_limit}$, le bundle **DOIT** être détruit et ne **DOIT PAS** être émis.

### 2.4. Rapports d'état de suppression (*Bundle Deletion Status Report*)
Lorsque le flag `deletion_report` (bit 14 des drapeaux de contrôle de traitement) est positionné par l'émetteur, le moteur DTN doit générer un bundle administratif de rapport d'état avec le code de raison standardisé :
- Raison `1` : `Lifetime expired`
- Raison `9` : `Hop limit exceeded`

### 2.5. L'Identité Canonique du Bundle : L'inutilité des `packet-id` ad-hoc
Une différence architecturale majeure entre le DTN et les réseaux maillés ad-hoc ou radioamateurs (APRS, Meshtastic) réside dans la gestion de l'unicité des messages :
- **En AX.25 (APRS) :** Les trames UI ne possèdent aucun identifiant de message au niveau liaison. Les digipeaters ont dû inventer un hash ad-hoc : $\text{hash}(\text{source}, \text{dest}, \text{info})$ pour détecter les doublons.
- **En Meshtastic :** L'entête LoRa insère un entier pseudo-aléatoire de 32 bits (`packet_id`).
- **En DTN (BPv7 RFC 9171 Section 4.2.2) :** Tout bundle possède **nativement** une identité universelle, canonique et mondialement unique :
  $$\text{BundleID} = (\text{source\_eid}, \text{creation\_timestamp.time}, \text{creation\_timestamp.sequence\_number})$$

Même sur les nœuds sans horloge (`time == 0`), le numéro de séquence monotone garantit cette unicité par station émettrice. Dans nos politiques Rego, la déduplication et les vecteurs de résumé reposent directement sur ce tuple ([helpers.rego](./policies/helpers.rego)) via `helpers.get_bundle_id(bundle)`. Aucun champ d'identifiant de message spécifique n'a besoin d'être surajouté dans un bloc d'extension.

De même, le **Hop Count Block (Type 10)** s'impose comme le garde-fou universel : tout algorithme mesh (qu'il s'agisse de Meshtastic ou d'APRS WIDE n-N) réconcilie son décompte de sauts avec ce bloc standard.

### 2.6. Protection Contre le Déni de Service (DoS) et Nœuds Malveillants : `blacklist_sources`
Dans les réseaux maillés et opportunistes ouverts (radioamateurs VHF/AX.25, capteurs LoRa, réseaux tactiques d'urgence), n'importe quelle station à portée radio peut injecter des trames dans l'éther. En cas de défaillance matérielle (nœud qui boucle et sature la fréquence) ou d'attaque malveillante par épuisement des ressources mémoire (*Storage Exhaustion Attack*), un routeur DTN doit pouvoir bloquer l'émetteur sans délai.

Plutôt que de recompiler ou de redémarrer le démon DTN, nous intégrons dans le contexte du nœud le champ `blacklist_sources: [* tstr]` ([mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl)). Dès l'arrivée d'un bundle, la politique d'Ingress vérifie si l'EID source figure dans cette liste :
- Le bundle est immédiatement rejeté (`DROP`) avant toute allocation de mémoire ou persistance sur disque.
- **Règle de sécurité cruciale :** Le nœud **ne génère aucun rapport d'état de suppression** (`generate_status_report := false`). Répondre systématiquement à un émetteur malveillant créerait un risque d'amplification de trafic et achèverait de saturer le canal radio partagé.

---

## 3. Architecture des Politiques Déclaratives : Le Découpage en 3 Étapes

Il est inefficace et conceptuellement erroné d'avoir une politique monolithique unique. Dans un système DTN, la décision d'acheminement intervient à trois moments distincts du cycle de vie du bundle :

```
                  +-----------------------------------+
                  |         Bundle Arrive (CLA)       |
                  +-----------------------------------+
                                    |
                                    v
                     [ 1. Ingress Policy (on_rx) ]
                                    |
                       +------------+------------+
                       |                         |
                   [ACCEPT]                    [DROP]
                       |                         |
                       v                         v
            +--------------------+       (Optionnel: Status Report)
            |    Bundle Store    |
            +--------------------+
               |              |
               | (périodique) | (opportunité CLA)
               v              v
      [ 2. Storage Policy ]  [ 3. Contact Policy ]
         (Audit / GC)          (Forwarding)
               |                      |
            [DROP / RETAIN]      [FORWARD / SKIP / DROP]
```

### Étape 1 : Ingress Policy (`dtn.ingress`) — Réception immédiate
* **Quand ?** Dès qu'un bundle est extrait d'un lien CLA (LoRa, AX.25, TCPCL).
* **Entrées :** `bundle`, `node.local_eid`, `node.blacklist_sources`, `ingress.peer_eid`, `current_dtn_time_ms`.
* **Rôle :**
  0. Si `source` figure dans `blacklist_sources` : `DROP` immédiat sans rapport d'état (anti-spam / DoS).
  1. Si `destination == local_eid` : délivrance locale prioritaire (`DELIVER_LOCAL`).
  2. Si `is_lifetime_expired` : `DROP` (code 1).
  3. Si `will_exceed_hop_limit` : `DROP` (code 9).
  4. Sinon : `ACCEPT` avec mutation CBOR obligatoire : `hop_count = hop_count + 1`.

### Étape 2 : Storage Audit Policy (`dtn.storage`) — Garbage Collector périodique
* **Quand ?** Exécuté périodiquement par un timer (ex: toutes les 10 secondes ou 1 minute) ou lors d'une alerte de mémoire saturée.
* **Entrées :** `bundle`, `current_dtn_time_ms`, `elapsed_since_last_audit_ms`.
* **Rôle :**
  1. Vérifier si la durée de vie a expiré pendant la rétention en mémoire tampon. Si oui, `DROP` (code 1).
  2. Si le bundle est un bundle sans horloge (`time == 0`), ordonner la mutation du **Bundle Age Block (Type 7)** pour ajouter le temps passé en stockage.

### Étape 3 : Contact Policy (`dtn.contact`) — Opportunité de liaison CLA
* **Quand ?** Lorsqu'un lien avec un nœud voisin est détecté ou qu'une liaison CLA s'établit.
* **Entrées :** `bundle`, `node`, `contact.peer_eid`, `contact.cla_type`, `current_dtn_time_ms`.
* **Rôle :**
  1. Revérifier la validité temporelle et la limite de sauts avant émission.
  2. Vérifier l'évitement de boucle immédiate (*Split Horizon*) : ne pas renvoyer le bundle au nœud amont immédiat indiqué dans le **Previous Node Insertion Block (Type 6)** (`SKIP`).
  3. Décider du renvoi : `FORWARD` si le contact est la destination finale ou un relais opportuniste valide.

---

## 4. Spécification et Implémentation Rego

L'ensemble des règles est implémenté et validé dans le répertoire [`policies/`](./policies).

### 4.1. Constantes et Aides ([dtn_constants.rego](./policies/dtn_constants.rego) & [helpers.rego](./policies/helpers.rego))

```rego
package dtn.helpers

import future.keywords.if
import future.keywords.in
import data.dtn.constants

# Détection unifiée de l'expiration temporelle
is_lifetime_expired(bundle, current_dtn_time_ms) if {
    bundle.primary.creation_timestamp.time > 0
    expiration_time := bundle.primary.creation_timestamp.time + bundle.primary.lifetime
    current_dtn_time_ms >= expiration_time
}

is_lifetime_expired(bundle, _) if {
    bundle.primary.creation_timestamp.time == 0
    age_block := get_extension_block(bundle.extension_blocks, constants.block_type_bundle_age)
    age_block.bundle_age_ms >= bundle.primary.lifetime
}

# Détection de dépassement de limite de saut
will_exceed_hop_limit(bundle) if {
    hcb := get_hop_count_block(bundle)
    (hcb.hop_count + 1) >= hcb.hop_limit
}
```

### 4.2. Politique d'Ingress ([ingress.rego](./policies/ingress.rego))

```rego
package dtn.ingress

import data.dtn.constants
import data.dtn.helpers

# 0. Rejet immédiat si la source est blacklistée (Anti-Spam / DoS)
decision := {
    "action": "DROP",
    "reason_code": constants.reason_depleted_storage,
    "reason": "Source EID is blacklisted on this node",
    "generate_status_report": false,
    "mutations": []
} if {
    helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
}

# 1. Livraison locale
decision := {
    "action": "DELIVER_LOCAL",
    "reason": "Destination matches local node",
    "generate_status_report": false,
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination == input.node.local_eid
}

# 2. Expiration de la Lifetime à l'arrivée
decision := {
    "action": "DROP",
    "reason_code": constants.reason_lifetime_expired,
    "reason": "Bundle lifetime has expired upon arrival",
    "generate_status_report": helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination != input.node.local_eid
    helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 3. Dépassement de la limite de saut
decision := {
    "action": "DROP",
    "reason_code": constants.reason_hop_limit_exceeded,
    "reason": "Hop limit exceeded after ingress hop increment",
    "generate_status_report": helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    helpers.will_exceed_hop_limit(input.bundle)
}

# 4. Acceptation et incrémentation du saut
decision := {
    "action": "ACCEPT",
    "reason": "Bundle accepted for forwarding / storage",
    "generate_status_report": false,
    "mutations": [{
        "block_type": constants.block_type_hop_count,
        "operation": "SET_FIELD",
        "field": "hop_count",
        "value": hop_block.hop_count + 1
    }]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.will_exceed_hop_limit(input.bundle)
    hop_block := helpers.get_hop_count_block(input.bundle)
}
```

### 4.3. Politique de Rétention en Stockage ([storage.rego](./policies/storage.rego))

```rego
package dtn.storage

import data.dtn.constants
import data.dtn.helpers

decision := {
    "action": "DROP",
    "reason_code": constants.reason_lifetime_expired,
    "reason": "Bundle lifetime expired during storage retention",
    "generate_status_report": helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}
```

### 4.4. Politique de Contact CLA ([contact.rego](./policies/contact.rego))

```rego
package dtn.contact

import data.dtn.constants
import data.dtn.helpers

# Évitement de boucle : ne pas réexpédier au nœud amont immédiat
decision := {
    "action": "SKIP",
    "reason": "Peer is the previous sender (split-horizon / loop avoidance)",
    "generate_status_report": false,
    "mutations": []
} if {
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_hop_limit_reached(input.bundle)
    pib := helpers.get_extension_block(input.bundle.extension_blocks, constants.block_type_previous_node)
    pib.previous_node == input.contact.peer_eid
}
```

---

## 5. Validation par les Tests Unitaires OPA

La suite de tests unitaires valide l'intégralité des chemins d'exécution et s'exécute directement via la CLI `opa` :

```bash
opa test ./policies -v
```

**Résultats obtenus :**
```text
./policies/contact_test.rego:
data.dtn.contact_test.test_contact_drop_expired: PASS (2.05ms)
data.dtn.contact_test.test_contact_drop_hop_limit_reached: PASS (964µs)
data.dtn.contact_test.test_contact_skip_previous_node: PASS (1.10ms)
data.dtn.contact_test.test_contact_forward_direct_destination: PASS (1.57ms)
data.dtn.contact_test.test_contact_forward_opportunistic_relay: PASS (1.33ms)

./policies/ingress_test.rego:
data.dtn.ingress_test.test_ingress_local_delivery: PASS (504µs)
data.dtn.ingress_test.test_ingress_drop_lifetime_expired_timed: PASS (1.08ms)
data.dtn.ingress_test.test_ingress_drop_lifetime_expired_untimed: PASS (1.13ms)
data.dtn.ingress_test.test_ingress_drop_hop_limit_reached: PASS (1.55ms)
data.dtn.ingress_test.test_ingress_accept_and_mutate_hop_count: PASS (1.35ms)
data.dtn.ingress_test.test_ingress_drop_blacklisted_source: PASS (698µs)

./policies/storage_test.rego:
data.dtn.storage_test.test_storage_drop_lifetime_expired_timed: PASS (403µs)
data.dtn.storage_test.test_storage_drop_lifetime_expired_untimed: PASS (706µs)
data.dtn.storage_test.test_storage_retain_and_update_age: PASS (1.19ms)
--------------------------------------------------------------------------------
PASS: 14/14 (politiques de base)
```

---

## 6. Questions et Perspectives pour les Prochains Articles

Ce socle fonctionnel ouvre des problématiques majeures à traiter lors de la transposition d'algorithmes mesh plus avancés :

1. **Gestion de la congestion et éviction de buffer :**  
   Si le stockage local est plein (`storage_used >= storage_capacity`), quel bundle supprimer ? Une politique FIFO aveugle ? Le bundle avec la plus petite durée de vie restante ? Ou une politique d'éviction basée sur l'utilité globale (comme MaxProp) ?
2. **Rétroaction des Status Reports :**  
   Si OPA ordonne `generate_status_report = true`, le démon DTN doit générer un bundle administratif vers la source. Comment éviter que ces rapports ne créent eux-mêmes une tempête d'inondation sur un réseau radio contraint ?
3. **Contraintes des couches de convergence (CLA) :**  
   Certains liens (ex: LoRa avec duty cycle de 1%, ou AX.25 à 1200 bauds) ne peuvent pas accepter de gros bundles. L'objet `input.contact` devra exposer la MTU et le débit estimé pour filtrer les bundles trop volumineux.
4. **Mutations CBOR complexes :**  
   Dans cet article, la seule mutation était l'incrémentation du champ `hop_count`. Pour APRS, la mutation consistera à consommer un alias `WIDE1-1 -> WIDE1*` et à apposer l'indicatif du relais dans un bloc de trace. Pour Spray and Wait, il s'agira de diviser un quota de réplication $L \leftarrow \lfloor L/2 \rfloor$.

Dans le prochain article (**Article 1**), nous nous attaquerons directement à la transposition du **digipeating APRS (AX.25)** : formalisation du nouveau bloc d'extension de chemin futur (*Path Trajectory Block*) et écriture des règles Rego associées.

---

👉 **Article suivant :** [Article 1 — Transposer le Digipeating APRS (AX.25 WIDE n-N) en DTN (BPv7)](./article-1-aprs.md)
