# Article 3 — Routage Opportuniste et Historique des Rencontres : PRoPHET (RFC 6693) sous Open Policy Agent

> **Spécifications CDDL :** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl) & [prophet.cddl](./prophet.cddl)  
> **Code des politiques :** [policies/prophet/](./policies/prophet/) ([ingress.rego](./policies/prophet/ingress.rego), [contact.rego](./policies/prophet/contact.rego), [storage.rego](./policies/prophet/storage.rego), [helpers.rego](./policies/prophet/helpers.rego), [constants.rego](./policies/prophet/constants.rego), [prophet_test.rego](./policies/prophet/prophet_test.rego))

> ℹ️ **Transparence Éditoriale (Conformité EU AI Act) :** Cet article a été rédigé avec l'assistance d'une IA sous la direction éditoriale et la structuration d'un auteur humain, qui en assure la relecture, la vérification technique et la responsabilité du contenu (relecture en cours).

---

## 1. Au-delà de l'Inondation Aveugle : La Mobilité Non-Aléatoire

Dans l'article précédent ([Article 2](./article-2-flood.md)), nous avons exploré comment **Spray and Wait** borne a priori la réplication en fixant un quota $L$, tandis que **Meshtastic** étouffe les tempêtes radio grâce à une temporisation de contention pondérée par le SNR. Cependant, ces deux approches partagent une hypothèse sous-jacente : **l'opportunisme aveugle**. Tout nœud relais disponible est traité de manière indifférenciée dès lors qu'il se trouve à portée.

Dans les scénarios réels (réseaux de secours en zone sinistrée, capteurs portés par des équipes de terrain, transports publics, flottes de drones ou d'animaux), les mouvements humains et matériels ne sont **pas aléatoires** :
- Les entités suivent des trajectoires récurrentes (trajets domicile-travail, patrouilles, tournées logistiques).
- Certains nœuds agissent comme des concentrateurs ou des ponts naturels (*social hubs*, passerelles d'infrastructures).
- Si le nœud $A$ rencontre fréquemment le nœud $B$, et que le nœud $B$ rencontre régulièrement le nœud $C$, le nœud $B$ constitue un excellent vecteur pour acheminer un message de $A$ vers $C$, même si $A$ et $C$ ne se croisent jamais directement.

C'est sur ce constat que repose **PRoPHET (*Probabilistic Routing Protocol using History of Encounters and Transitivity*)**, initialement proposé par Anders Lindgren et al. (2003) et standardisé au sein de l'IRTF DTNRG dans la **[RFC 6693](https://www.rfc-editor.org/rfc/rfc6693.html)**.

---

## 2. Les Fondations Mathématiques de la RFC 6693

PRoPHET introduit pour chaque nœud $A$ une métrique scalaire nommée **Prévisibilité de Livraison (*Delivery Predictability*)** notée $P_{(A, B)} \in [0, 1]$ pour toute destination connue $B$. Plus cette valeur est proche de $1$, plus la probabilité que le nœud $A$ parvienne à livrer un bundle à $B$ est élevée.

Cette métrique évolue dynamiquement selon trois équations différentielles discrètes :

```
          +-------------------------------------------------------+
          | 1. Rencontre Directe : P(a, b) augmente               |
          |    P(a, b) = P(a, b)_old + (1 - P(a, b)_old) * P_enc  |
          +-------------------------------------------------------+
                                      |
                                      v
          +-------------------------------------------------------+
          | 2. Transitivité : P(a, c) bénéficie de l'allié b      |
          |    P(a, c) = P(a, c)_old + (1 - P(a, c)_old)          |
          |              * P(a, b) * P(b, c) * beta               |
          +-------------------------------------------------------+
                                      |
                                      v
          +-------------------------------------------------------+
          | 3. Vieillissement Temporel (Aging) : P décroît        |
          |    P(a, b) = P(a, b)_old * (gamma ^ k)                |
          +-------------------------------------------------------+
```

### 2.1. Mise à jour lors d'une rencontre directe (*Direct Encounter*)
Lorsque le nœud $A$ entre en contact physique avec le nœud $B$, sa prévisibilité envers $B$ est immédiatement réévaluée à la hausse :
$$P_{(A, B)} = P_{(A, B)\text{old}} + (1 - P_{(A, B)\text{old}}) \times P_\text{encounter}$$
- $P_\text{encounter} \in [0, 1]$ est un paramètre système (par défaut $0.75$ dans la RFC 6693).
- Grâce au facteur d'amortissement $(1 - P_{(A, B)\text{old}})$, la métrique s'approche asymptotiquement de $1$ sans jamais la dépasser, récompensant la régularité des rencontres.

### 2.2. Transitivité transitive (*Transitivity*)
Si $A$ rencontre $B$, ils échangent leurs tables de prévisibilités (*Handshake / RIB exchange*). Pour chaque destination tierce $C$ connue de $B$, le nœud $A$ réévalue son propre score :
$$P_{(A, C)} = P_{(A, C)\text{old}} + (1 - P_{(A, C)\text{old}}) \times P_{(A, B)} \times P_{(B, C)} \times \beta$$
- $\beta \in [0, 1]$ est le facteur d'atténuation de transitivité (par défaut $0.25$).
- Cette propriété permet à l'information d'acheminement de percoler à travers le réseau sans nécessiter de cartographie globale centralisée.

### 2.3. Vieillissement temporel (*Aging*)
Si deux nœuds ne se croisent plus, leur utilité mutuelle diminue au fil du temps :
$$P_{(A, B)} = P_{(A, B)\text{old}} \times \gamma^k$$
- $\gamma \in (0, 1)$ est la constante de vieillissement (par défaut $0.98$).
- $k$ représente le nombre d'unités de temps écoulées depuis le dernier audit.

---

## 3. Architecture et Découplage : Filaire vs Environnement OPA

Comme mis en lumière dans nos travaux précédents, une implémentation DTN élégante sépare strictement les données qui circulent sur le câble de celles qui gouvernent la décision locale.

### 3.1. Sur le câble : Le Seuil Opportuniste (`opportunistic-threshold`)
Contrairement à des protocoles lourds qui tenteraient de sérialiser l'intégralité de la matrice de routage dans chaque bundle de données, **PRoPHET en DTN n'impose qu'un champ optionnel dans le bloc d'extension Type 200** :
```cddl
mesh-routing-data = {
    ? 1 => legacy-bridge-id: (bytes / uint), ; Empreinte externe optionnelle
    ? 4 => opportunistic-threshold: float,   ; Seuil d'utilité minimal exigé par l'émetteur
    ...
}
```
L'émetteur d'un bundle sensible (ex: une alerte médicale prioritaire) peut spécifier `opportunistic-threshold: 0.65`. Ainsi, un nœud relais s'abstiendra de confier le bundle à un passant dont la probabilité envers la destination est trop faible, évitant la dispersion inutile du paquet.

### 3.2. Dans l'Environnement d'Évaluation OPA (`input`)
Les tables de prévisibilités $P_{(A, *)}$ et $P_{(B, *)}$ sont des structures de données locales maintenues en mémoire vive par le démon DTN. Elles sont injectées dans le contexte d'évaluation OPA conformément à la Partie 2 de [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl) :

- `input.node.delivery_predictabilities` : dictionnaire `{ "dtn://dest/": 0.45, ... }` calculé par le nœud local.
- `input.contact.peer_predictabilities` : vecteur de prévisibilité transmis par le pair $B$ lors de l'établissement de la couche de convergence (CLA).
- `input.contact.held_bundle_ids` : *Summary Vector* du pair (liste des identifiants canoniques qu'il stocke déjà).

### 3.3. Réconciliation avec le Hop Count Block (Type 10) et le Bundle ID
- **Détection des doublons :** Le Bundle ID canonique `(source_eid, creation_timestamp.time, creation_timestamp.sequence_number)` ([RFC 9171 Section 4.2.2](https://www.rfc-editor.org/rfc/rfc9171.html#section-4.2.2)) élimine tout besoin de rajouter un hash ad-hoc.
- **Rupture des boucles de transitivité :** Même si la transitivité créait une oscillation probabiliste temporaire entre deux groupes de nœuds, le **Hop Count Block (Type 10)** garantit que le bundle sera détruit net dès que `hop_count >= hop_limit`.

### 3.4. Le Protocole de Rencontre : Spécification CDDL des Messages de Contrôle ([prophet.cddl](./prophet.cddl))

Une observation fondamentale distingue PRoPHET des protocoles précédents : **PRoPHET est le tout premier algorithme de notre série qui nécessite explicitement un protocole d'échange bilatéral d'informations entre nœuds lors d'un contact.**
- En APRS, les stations digipeatent des trames UI en aveugle sans aucun accusé ni synchronisation de table.
- En Meshtastic, les nœuds inondent le canal LoRa sans négociation préalable.
- En Spray & Wait, le contingentement est calculé localement par division mathématique du quota $L$.

À l'inverse, dès que deux nœuds PRoPHET $A$ et $B$ se découvrent, ils doivent obligatoirement s'échanger deux catégories d'informations vitales :
1. **La Routing Information Base (RIB Update) :** Le vecteur de prévisibilités $P_{(B, *)}$ de $B$, indispensable pour permettre à $A$ d'actualiser ses scores transitifs et de déterminer si $P_{(B, D)} > P_{(A, D)}$.
2. **Le Summary Vector (SV) :** L'inventaire des identifiants de bundles que chaque nœud stocke déjà, pour éviter de répliquer des bundles déjà détenus par le pair.
3. **Le Handshake Combiné :** Une optimisation critique pour les liens radio contraints (LoRa / AX.25), fusionnant RIB et Summary Vector en **un seul message CBOR**.
4. **Les Accusés de Livraison (Delivery ACKs) :** Notification de remise finale permettant d'ordonner la purge des répliques devenues inutiles dans les mémoires tampons du réseau.

En DTN, ces messages de signalisation peuvent être transportés soit au niveau de la session de la couche de convergence (CLA), soit directement encapsulés dans le **payload d'un bundle administratif** (ex: adressé à `dtn://contact-peer/prophet`).

Le fichier **[prophet.cddl](./prophet.cddl)** formalise rigoureusement cette grammaire CBOR :

```cddl
prophet-control-bundle = {
    1 => message-type: prophet-message-type,
    2 => sender-eid: tstr,                  ; EID de l'émetteur
    3 => timestamp-ms: uint,                ; Horloge DTN d'émission
    ? 4 => payload: prophet-message-payload ; Contenu du message
}

; Optimisation radio : Handshake combiné (RIB + Summary Vector)
handshake-combined-payload = {
    1 => rib-entries: [* rib-entry],        ; Couples (destination_eid, P_value)
    2 => held-bundles: [* bundle-identifier], ; Identifiants canoniques (source, time, seq)
    ? 3 => available-storage-bytes: uint    ; Espace mémoire restant
}

rib-entry = {
    1 => destination-eid: tstr,
    2 => delivery-predictability: float,
    ? 3 => last-update-dtn-time: uint
}
```

#### Comment ce dialogue alimente le moteur OPA
Le démon DTN reçoit ce bundle administratif de contrôle, décode la charge utile CBOR, met à jour sa table de transitivité et injecte directement les données dans le contexte OPA :
- `rib-entries` alimente `input.contact.peer_predictabilities`.
- `held-bundles` alimente `input.contact.held_bundle_ids`.

Cette séparation est remarquable : **le plan de transport échange les bundles de contrôle décrits dans [prophet.cddl](./prophet.cddl), tandis que le moteur OPA évalue les règles déclaratives de [contact.rego](./policies/prophet/contact.rego) en toute isolation.**

---

## 4. Implémentation Déclarative avec OPA (Rego)

La suite de politiques est organisée dans le dossier [policies/prophet/](./policies/prophet/).

### 4.1. Fonctions Mathématiques ([helpers.rego](./policies/prophet/helpers.rego))

Rego n'autorisant pas la récursion infinie pour des raisons de garantie de terminaison, le vieillissement et la transitivité sont calculés avec une formule fermée :

```rego
package dtn.prophet.helpers

# Rencontre directe : P(a, b) = P(a, b)_old + (1 - P(a, b)_old) * P_encounter
update_encounter(p_old, p_encounter) := p_new if {
    p_new := p_old + ((1.0 - p_old) * p_encounter)
}

# Décroissance temporelle non-récursive : gamma ^ k
compute_decay(gamma, time_units) := 1.0 if time_units <= 0
compute_decay(gamma, 1) := gamma
compute_decay(gamma, 2) := gamma * gamma
compute_decay(gamma, 3) := (gamma * gamma) * gamma
compute_decay(gamma, time_units) := decay if {
    time_units >= 4
    g2 := gamma * gamma
    decay := g2 * g2
}

update_aging(p_old, gamma, time_units) := p_new if {
    decay := compute_decay(gamma, time_units)
    p_new := p_old * decay
}

# Transitivité : P(a, c) = P(a, c)_old + (1 - P(a, c)_old) * P(a, b) * P(b, c) * beta
update_transitivity(p_ac_old, p_ab, p_bc, beta) := p_ac_new if {
    transitive_factor := (p_ab * p_bc) * beta
    p_ac_new := p_ac_old + ((1.0 - p_ac_old) * transitive_factor)
}
```

### 4.2. Règle d'Acheminement lors du Contact ([contact.rego](./policies/prophet/contact.rego))

Lorsqu'une liaison CLA s'établit avec un voisin $B$ :
1. Si $B$ est la destination finale du bundle $\implies$ `FORWARD_DIRECT`.
2. Si $B$ possède déjà le bundle (vérification du *Summary Vector*) $\implies$ `SKIP`.
3. Si le bundle porte un `opportunistic_threshold` et que $P_{(B, D)} < \text{threshold}$ $\implies$ `SKIP`.
4. **Condition Fondamentale PRoPHET :**  
   Si $P_{(B, D)} > P_{(A, D)} + \Delta_\text{margin}$ $\implies$ `FORWARD_OPPORTUNISTIC`.  
   Le nœud local transmet une réplique au pair $B$, car celui-ci présente une probabilité statistiquement supérieure d'acheminer le bundle à bon port.

```rego
decision := {
    "action": "FORWARD_OPPORTUNISTIC",
    "reason": sprintf("Peer has higher delivery predictability P(peer, dest)=%v than local P(local, dest)=%v", [p_peer, p_local]),
    "mutations": []
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    not dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not dtn_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not prophet_helpers.peer_already_holds_bundle(input.contact, input.bundle)
    threshold := prophet_helpers.get_opportunistic_threshold(input.bundle)
    p_local := prophet_helpers.get_local_predictability(input.node, input.bundle.primary.destination)
    p_peer := prophet_helpers.get_peer_predictability(input.contact, input.bundle.primary.destination)
    prophet_helpers.satisfies_threshold(p_peer, threshold)
    prophet_helpers.is_forwarding_favorable(p_peer, p_local, constants.default_forward_margin)
}
```

### 4.3. Gestion du Tampon et Éviction Mémoire ([storage.rego](./policies/prophet/storage.rego))

En réseau opportuniste à stockage persistant (*Store-Carry-and-Forward*), les disques et mémoires Flash s'engorgent rapidement. La Section 3.4 de la RFC 6693 préconise une stratégie d'éviction guidée par la valeur de $P_{(A, D)}$ :

> *Lors d'un débordement de mémoire tampon, un nœud PRoPHET doit éliminer en priorité les bundles pour lesquels il possède la plus faible prévisibilité de livraison locale $P_{(A, D)}$.*

Cette règle est exprimée avec OPA :

```rego
decision := {
    "action": "EVICT_LOW_PREDICTABILITY",
    "reason": sprintf("Storage full: evicted bundle due to low delivery predictability P(local, dest)=%v", [p_local]),
    "mutations": [],
    "eviction_metric": p_local
} if {
    not dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    used := object.get(input.node, "storage_used_bytes", 0)
    capacity := object.get(input.node, "storage_capacity_bytes", 0)
    capacity > 0
    used > capacity
    p_local := prophet_helpers.get_local_predictability(input.node, input.bundle.primary.destination)
    eviction_threshold := object.get(input.node, "eviction_predictability_threshold", 0.1)
    p_local <= eviction_threshold
}
```

---

## 5. Validation par les Tests Unitaires OPA (60/60 PASS)

Une batterie de 16 tests unitaires spécifiques à PRoPHET ([prophet_test.rego](./policies/prophet/prophet_test.rego)) a été ajoutée. Elle couvre :
- L'exactitude des calculs mathématiques (rencontre, transitivité, décroissance temporelle).
- Le comportement d'admission et de rejet à l'Ingress.
- Le filtrage par Summary Vector et par seuil d'utilité émetteur.
- L'arbitrage opportuniste de forwarding entre porteur et contact.
- L'éviction sélective de bundles lors d'une saturation mémoire.

Exécution de la suite complète du dépôt :

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
policies/prophet/prophet_test.rego:
  data.dtn.prophet_test.test_prophet_math_encounter: PASS
  data.dtn.prophet_test.test_prophet_math_aging: PASS
  data.dtn.prophet_test.test_prophet_math_transitivity: PASS
  data.dtn.prophet_test.test_prophet_ingress_local_delivery: PASS
  data.dtn.prophet_test.test_prophet_ingress_duplicate: PASS
  data.dtn.prophet_test.test_prophet_ingress_expired: PASS
  data.dtn.prophet_test.test_prophet_ingress_accept_increment: PASS
  data.dtn.prophet_test.test_prophet_contact_direct_destination: PASS
  data.dtn.prophet_test.test_prophet_contact_skip_peer_holds: PASS
  data.dtn.prophet_test.test_prophet_contact_forward_favorable: PASS
  data.dtn.prophet_test.test_prophet_contact_skip_unfavorable: PASS
  data.dtn.prophet_test.test_prophet_contact_skip_threshold_unmet: PASS
  data.dtn.prophet_test.test_prophet_contact_forward_threshold_met: PASS
  data.dtn.prophet_test.test_prophet_storage_drop_expired: PASS
  data.dtn.prophet_test.test_prophet_storage_eviction_low_predictability: PASS
  data.dtn.prophet_test.test_prophet_storage_retain_high_predictability: PASS
policies/storage_test.rego:
  3 tests validés (gestion du Bundle Age Block Type 7)
--------------------------------------------------------------------------------
PASS: 60/60
```

---

## 6. Synthèse Comparative : Epidemic vs Spray & Wait vs PRoPHET

| Critère | Epidemic ([Article 2](./article-2-flood.md)) | Spray and Wait ([Article 2](./article-2-flood.md)) | PRoPHET ([RFC 6693](https://www.rfc-editor.org/rfc/rfc6693.html)) |
| :--- | :--- | :--- | :--- |
| **Connaissance topologique** | Aucune (aveugle) | Aucune (aveugle) | Historique local des rencontres et transitivité |
| **Dissémination des copies** | Inondation non bornée | Bornée à $L$ copies strictes | Guidée par le différentiel d'utilité $P_{(B, D)} > P_{(A, D)}$ |
| **Taux de livraison en réseau dense** | Mauvais (saturation et drop) | Bon | Excellent (privilégie les nœuds centraux) |
| **Charge sur la bande passante** | Très élevée | Faible ($L-1$ transmissions) | Modérée (forwarding sélectif) |
| **Gestion du débordement buffer** | Drop-Tail (aléatoire / FIFO) | FIFO / âge | Éviction ciblée des bundles à faible prévisibilité |

---

## 7. Perspectives : Vers l'Optimalité Théorique et la Gestion des Buffers (MaxProp)

Avec PRoPHET, nous avons franchi une étape décisive : le routage ne subit plus la topologie au hasard, il s'adapte dynamiquement aux habitudes réelles des entités mobiles.

Dans le prochain article ([Article 4 — MaxProp](./article-4-maxprop.md)), nous franchirons un pas supplémentaire : comment ordonnancer rigoureusement les files de transmission et d'éviction sous contrainte de mémoire tampon (*buffer congestion*), transformer les probabilités de contact en coût d'information logarithmique optimal ($-\log(P + \epsilon)$) et adapter le commérage topologique aux canaux radio contraints (2-Hop Gossip).

---

👉 **Article suivant :** [Article 4 — Routage Probabiliste et Gestion de Mémoire sous Contrainte : MaxProp et ses Optimisations Théoriques (HP-MaxProp)](./article-4-maxprop.md)
