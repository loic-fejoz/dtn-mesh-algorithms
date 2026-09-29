# Article 1 — Transposer le Digipeating APRS (AX.25 WIDE n-N) en DTN (BPv7) avec Open Policy Agent

> **Série :** *Transposition d'algorithmes de routage mesh & opportunistes vers DTN (BPv7)*  
> **Article précédent :** [Article 0 — Les Fondations du Routage DTN avec Open Policy Agent](file:///home/loic/projets/dtn-mesh-algorithm/article-0-intro.md)  
> **Spécification CDDL :** [mesh-algo-extension-block.cddl](file:///home/loic/projets/dtn-mesh-algorithm/mesh-algo-extension-block.cddl)  
> **Code des politiques :** [policies/aprs/](file:///home/loic/projets/dtn-mesh-algorithm/policies/aprs/) ([ingress.rego](file:///home/loic/projets/dtn-mesh-algorithm/policies/aprs/ingress.rego), [contact.rego](file:///home/loic/projets/dtn-mesh-algorithm/policies/aprs/contact.rego), [helpers.rego](file:///home/loic/projets/dtn-mesh-algorithm/policies/aprs/helpers.rego), [constants.rego](file:///home/loic/projets/dtn-mesh-algorithm/policies/aprs/constants.rego), [aprs_test.rego](file:///home/loic/projets/dtn-mesh-algorithm/policies/aprs/aprs_test.rego))

---

## 1. Introduction : L'héritage d'APRS et le paradigme New-N

Créé par Bob Bruninga (WB4APR) au début des années 1990, l'**APRS (Automatic Packet Reporting System)** est l'un des premiers réseaux maillés radioamateurs à large échelle au monde. Conçu pour fonctionner sur des fréquences VHF partagées (typiquement 144.800 MHz en Europe) via des trames non connectées **AX.25 UI (*Unnumbered Information*)**, APRS repose sur un mécanisme de relais simplifié appelé **digipeating**.

Dans l'entête AX.25, un émetteur spécifie une liste de répéteurs intermédiaires. Avec le paradigme moderne **New-N (WIDE n-N)** :
1. Un paquet émis avec la trajectoire `WIDE1-1, WIDE2-1` est d'abord capté par un répéteur de proximité (*fill-in digipeater*).
2. Ce relais décrémente le SSID `WIDE1-1` en `WIDE1*` (ou substitue son propre indicatif avec le bit H positionné : `F4KXL-1*`) et réémet la trame.
3. Un second répéteur d'altitude (*wide digipeater*) capte la trame, décrémente `WIDE2-1` en `WIDE2*`, et réémet.
4. Une fois tous les alias consommés (SSID = 0), aucun digipeater ne réémet le paquet.
5. Une fenêtre anti-doublon (généralement 30 secondes) empêche les boucles et les échos entre relais voisins.

### Pourquoi transposer ce mécanisme en DTN ?
Bien que brillant par sa simplicité, l'AX.25 traditionnel souffre de limitations sévères :
- Absence totale de chiffrement et d'authentification native (vulnérable au spoofing).
- Dépendance à un médium radio synchrone (pas de rétention tolérante aux délais prolongés).
- Format d'entête figé et limité à 8 sauts.

En transposant le digipeating APRS dans le **Bundle Protocol v7 ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html))**, nous bénéficions de la sécurité de bout en bout avec **BPSec ([RFC 9172](https://www.rfc-editor.org/rfc/rfc9172.html))**, de la rupture de boucle native par **Hop Count (Type 10)**, et du stockage persistant **Store-Carry-and-Forward**.

---

## 2. Spécification CBOR / CDDL : Le Bloc d'Extension Mesh

Pour concilier APRS et les futurs algorithmes (Spray & Wait, PRoPHET, Reticulum, Meshtastic), nous avons formalisé un bloc d'extension BPv7 unifié dans [mesh-algo-extension-block.cddl](file:///home/loic/projets/dtn-mesh-algorithm/mesh-algo-extension-block.cddl).

### 2.1. Dualité Passé vs Futur : TREB et Trajectory Block
Un point clé d'architecture mis en lumière dans nos réflexions :
- Le **Traceroute Extension Block (TREB - `draft-koo-dtn-traceroute-eb`)** consigne la **trajectoire passée** : quels nœuds ont déjà été traversés, à quel moment et avec quelles métriques.
- Notre nouveau bloc de routage mesh porte la **trajectoire future** : quels nœuds stricts ou alias génériques (`WIDE n-N`) doivent encore relayer le bundle.

### 2.2. Extrait de la spécification CDDL pour APRS

```cddl
; Bloc expérimental BPv7 modulaire et agnostique (Type 200)
mesh-routing-data = {
    ? 1 => legacy-bridge-id: (bytes / uint), ; Empreinte externe optionnelle (passerelle AX.25)
    ? 3 => trajectory-control,               ; Primitives de trajectoire future ordonnée
    ...
}

trajectory-control = {
    1 => path-elements: [* path-element],  ; Liste ordonnée des sauts futurs/passés
    2 => active-hop-index: uint,           ; Pointeur 0-based sur le saut actif
    ? 3 => allow-substitution: bool        ; Autorise la substitution de l'alias par l'identifiant réel
}

path-element = strict-target / scoped-alias

; Étape stricte vers un nœud ou indicatif précis (ex: "F4KXL-1")
strict-target = {
    1 => target-type: 1,                   ; 1 = Cible stricte
    2 => target-id: tstr,                  ; EID ou Callsign
    3 => completed: bool                   ; True si déjà relayé (bit H AX.25)
}

; Étape avec alias à portée générique (paradigme New-N : WIDE1-1, WIDE2-2, etc.)
scoped-alias = {
    1 => target-type: 2,                   ; 2 = Alias générique
    2 => scope-name: tstr,                 ; "WIDE1", "WIDE2", "RELAY", "LOCAL"
    3 => max-count: uint,                  ; Compte initial N
    4 => remaining-count: uint,            ; Compte restant décrémenté à chaque relais
    5 => completed: bool,                  ; True lorsque remaining-count == 0
    ? 6 => serviced-by: tstr               ; Identifiant réel de la station ayant relayé
}
```

### 2.3. Réconciliation avec le Hop Count Block (Type 10) et le Bundle ID

Deux arbitrages d'architecture majeurs émergent de cette transposition :

1. **Garde-fou global vs Sémantique de rôle :**  
   Pour un chemin APRS composite comme `WIDE1-1, WIDE2-2`, le nombre total maximal de sauts est de $1 + 2 = 3$. À l'émission du bundle, le **Hop Count Block (Type 10)** est initialisé avec `hop_limit = 3`. À chaque relais (qu'il s'agisse d'un `WIDE1`, d'un `WIDE2` ou d'un saut strict), le `hop_count` du bloc Type 10 est incrémenté de 1. Même si un relais défaillant oublie de décrémenter son alias, le bloc standard BPv7 détruit le bundle dès que la limite est atteinte.
2. **Dupe cache et Bundle ID :**  
   En AX.25 analogique, l'absence d'identifiant de message obligeait les digipeaters à fabriquer un hash éphémère $\text{hash}(\text{source}, \text{dest}, \text{info})$. En DTN, le **Bundle ID canonique** `(source_eid, time, seq)` remplit nativement et universellement ce rôle. Aucun champ d'identifiant dédié n'est donc nécessaire dans le bloc d'extension pour les nœuds DTN.

---

## 3. Logique de Décision et Politiques OPA (Rego)

La logique APRS est implémentée de manière déclarative dans [policies/aprs/](file:///home/loic/projets/dtn-mesh-algorithm/policies/aprs/).

```
                 [ Bundle Ingress (AX.25 / LoRa) ]
                                |
                                v
               +---------------------------------+
               |   Dupe Cache (30s) vérifié ?    |---(Oui)---> [ DROP ]
               +---------------------------------+
                                | (Non)
                                v
               +---------------------------------+
               | Le nœud est-il un Digipeater ?  |---(Non)---> [ DROP ]
               +---------------------------------+
                                | (Oui)
                                v
               +---------------------------------+
               |  Examen du saut actif (index)   |
               +---------------------------------+
                 /                             \
     (Saut Strict / Callsign)        (Alias Générique WIDE n-N)
               /                                 \
  +-------------------------+       +-------------------------------+
  | Correspond à mon nœud ? |       | L'alias est-il pris en charge?|
  +-------------------------+       +-------------------------------+
     /                   \               /                     \
  (Oui)                 (Non)          (Oui)                  (Non)
    |                     |              |                      |
[ ACCEPT ]             [ SKIP ]    +---------------+         [ SKIP ]
(Avance index,                     | remaining > 1 |
 digipeated=true)                  +---------------+
                                      /         \
                                   (Oui)       (Non, =1)
                                     |             |
                                [ ACCEPT ]     [ ACCEPT ]
                                (Décrémente    (remaining=0,
                                 remaining,     digipeated=true,
                                 index stable)  avance index)
```

### 3.1. Politique d'Ingress ([ingress.rego](file:///home/loic/projets/dtn-mesh-algorithm/policies/aprs/ingress.rego))

#### Règle 1 : Déduplication immédiate (Dupe Suppression Cache)
Comme en APRS analogique, un digipeater ignore un paquet s'il a déjà été traité récemment :
```rego
decision := {
    "action": "DROP",
    "reason": "Duplicate packet detected in seen cache",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    helpers.is_duplicate(input.bundle, input.node.seen_cache)
}
```

#### Règle 2 : Décrémentation d'un Alias `WIDEn-N` (`remaining_hops > 1`)
Exemple : un paquet arrive avec `WIDE2-2`. Le nœud local `F4KXL-1` accepte l'alias `WIDE2` :
- Il décrémente `remaining_hops` à `1`.
- Il substitue son indicatif (`substituted_by: "F4KXL-1"`).
- **Le pointeur `active_hop_index` reste sur cet élément**, car il reste un bond `WIDE2-1` à consommer par le prochain relais !
```rego
decision := {
    "action": "ACCEPT_DIGIPEAT",
    "reason": sprintf("Generic alias %v decremented to %v", [hop.alias_name, hop.remaining_hops - 1]),
    "mutations": [{
        "block_type": 200,
        "operation": "MUTATE_APRS_PAYLOAD",
        "active_hop_index": block.payload.active_hop_index, # Toujours sur ce saut
        "updated_hop_index": block.payload.active_hop_index,
        "updated_hop": object.union(hop, {
            "remaining_hops": hop.remaining_hops - 1,
            "substituted_by": input.node.callsign
        }),
        "cache_hash": block.payload.dupe_suppression_hash
    }]
} if {
    ...
    hop.hop_kind == constants.hop_kind_alias
    helpers.is_alias_supported(hop.alias_name, input.node.supported_aliases)
    hop.remaining_hops > 1
}
```

#### Règle 3 : Consommation finale d'un Alias (`remaining_hops == 1`)
Exemple : un paquet arrive avec `WIDE1-1` ou `WIDE2-1` :
- `remaining_hops` passe à `0`.
- `digipeated` passe à `true`.
- **Le pointeur `active_hop_index` avance de 1** pour passer au prochain saut de la trajectoire.
```rego
decision := {
    "action": "ACCEPT_DIGIPEAT",
    "reason": sprintf("Generic alias %v fully consumed", [hop.alias_name]),
    "mutations": [{
        "block_type": 200,
        "operation": "MUTATE_APRS_PAYLOAD",
        "active_hop_index": block.payload.active_hop_index + 1, # Passe au saut suivant
        "updated_hop_index": block.payload.active_hop_index,
        "updated_hop": object.union(hop, {
            "remaining_hops": 0,
            "digipeated": true,
            "substituted_by": input.node.callsign
        }),
        "cache_hash": block.payload.dupe_suppression_hash
    }]
} if {
    ...
    hop.remaining_hops == 1
}
```

#### Règle 4 : Saut Strict (Source Routing explicite)
Si l'élément de chemin est un nœud précis (ex: `F4KXL-1`) :
- Si l'indicatif correspond au nœud local : le saut est validé, marqué `digipeated = true`, et l'index avance (`ACCEPT_DIGIPEAT`).
- Si l'indicatif est destiné à une autre station : le paquet est ignoré (`SKIP`).

---

## 4. Conformité aux Recommandations Dire Wolf (WB2OSZ - *APRS-Digipeaters.pdf*)

Dans son document de référence [*APRS Digipeaters* (John Langner, WB2OSZ)](https://github.com/wb2osz/direwolf-doc/blob/main/APRS-Digipeaters.pdf), l'auteur de Dire Wolf formalise les exigences d'un digipeater moderne et bien luné face aux incohérences des anciens firmwares (TNC-2, KPC-3+). Notre implémentation DTN respecte rigoureusement ces recommandations :

| Règle Dire Wolf (*APRS-Digipeaters.pdf*) | Spécification WB2OSZ | Implémentation DTN / OPA | Test associé |
| :--- | :--- | :--- | :--- |
| **Section 6.1(b)** | *Is the source my station address? If so, return NO.* | Détection immédiate via `helpers.is_own_packet`. Le paquet est immédiatement `DROP` pour empêcher les boucles d'écho. | `test_aprs_direwolf_6_1b_suppress_own_packet` |
| **Section 6.2(a)** | *Suppress any duplicates (30 seconds cache on source, dest, info).* | Filtrage par `helpers.is_duplicate` sur le hash de déduplication (exposé dans `node.seen_cache`). | `test_aprs_duplicate_suppression` |
| **Section 6.3(a) & 7** | *Adaptive insertion / replacement for $N \ge 2$.* | Pour `WIDEn-N` ($N \ge 2$), décrémentation de `remaining_hops`, apposition de l'indicatif dans `substituted_by`, et maintien de l'index sur le saut. | `test_aprs_generic_alias_decremented` |
| **Section 6.3(b) & 7** | *When $N = 1$, replace by callsign and mark as used (no $N=0$ dangling).* | Contrairement au bug des vieux TNC (KPC-3+ v8.2) qui laissaient des `WIDE1*` résiduels, l'alias est marqué `digipeated: true` et le pointeur avance au saut suivant. | `test_aprs_generic_alias_fully_consumed` |
| **Section 6.3(c)** | *If $N = 0$, hop count is used up: do NOT repeat.* | Rejet strict si un paquet arrive avec un alias dont `remaining_hops <= 0` non marqué digipeated. | `test_aprs_direwolf_6_3c_drop_exhausted_alias` |
| **Section 10** | *Trapping larger values of N (`^WIDE[3-7]-[1-7]$`).* | Protection contre la saturation radio : les alias configurés dans `trapped_aliases` sont clampés et relayés une seule et unique fois. | `test_aprs_direwolf_section_10_trapping_excessive_alias` |

---

## 5. Validation par les Tests Unitaires OPA (25/25 PASS)

La suite de tests unitaires dédiée ([aprs_test.rego](file:///home/loic/projets/dtn-mesh-algorithm/policies/aprs/aprs_test.rego)) valide 12 scénarios représentatifs :

```bash
opa test ./policies -v
```

```text
/home/loic/projets/dtn-mesh-algorithm/policies/aprs/aprs_test.rego:
data.dtn.aprs_test.test_aprs_local_delivery: PASS (906µs)
data.dtn.aprs_test.test_aprs_duplicate_suppression: PASS (2.08ms)
data.dtn.aprs_test.test_aprs_strict_hop_matched: PASS (4.15ms)
data.dtn.aprs_test.test_aprs_strict_hop_not_for_me: PASS (4.08ms)
data.dtn.aprs_test.test_aprs_generic_alias_decremented: PASS (7.42ms)
data.dtn.aprs_test.test_aprs_generic_alias_fully_consumed: PASS (3.80ms)
data.dtn.aprs_test.test_aprs_unsupported_alias: PASS (4.40ms)
data.dtn.aprs_test.test_aprs_contact_broadcast: PASS (389µs)
data.dtn.aprs_test.test_aprs_contact_unicast_match: PASS (572µs)
data.dtn.aprs_test.test_aprs_direwolf_6_1b_suppress_own_packet: PASS (1.26ms)
data.dtn.aprs_test.test_aprs_direwolf_6_3c_drop_exhausted_alias: PASS (3.18ms)
data.dtn.aprs_test.test_aprs_direwolf_section_10_trapping_excessive_alias: PASS (4.54ms)
--------------------------------------------------------------------------------
Total global : 25/25 tests PASS (13 fondations + 12 APRS)
```

---

## 6. Ce que cette approche apporte au monde Radioamateur & Mesh

1. **Flexibilité totale des règles de relais :**  
   Plus besoin de recompiler un firmware TNC ou un démon AX.25 pour adapter son comportement. En modifiant simplement la politique Rego, un opérateur peut :
   - Désactiver le support de `WIDE2` la nuit ou sous faible tension batterie.
   - Activer ou désactiver le *trapping* selon la densité locale du trafic radio.
   - Restreindre le digipeating aux seuls paquets émis par des balises d'urgence (SAR) ou météo.
2. **Encapsulation sécurisée :**  
   Les paquets APRS ne sont plus des trames AX.25 en texte clair vulnérables à l'usurpation. Ils bénéficient des signatures BPSec (BIB) et peuvent transiter indifféremment sur de la VHF 1200 bauds, du LoRa ou des liens IP/AREDN de façon transparente.
3. **Synergie Passé/Futur :**  
   Le couplage entre notre bloc de trajectoire future et le **Traceroute Extension Block (TREB)** standard permet une visibilité totale du parcours d'un paquet sans alourdir le routage.

Dans le prochain article (**Article 2**), nous transposerons le protocole **Spray and Wait** : gestion des quotas de réplication ($L$), distribution binaire ($L/2$) et transition dynamique vers la phase *Wait*.
