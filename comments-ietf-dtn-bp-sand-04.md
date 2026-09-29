# Commentaires et Retours Techniques sur `draft-ietf-dtn-bp-sand-04`
## Secure Advertisement and Neighborhood Discovery (SAND) for BPv7

> **Document examiné :** `draft-ietf-dtn-bp-sand-04` (8 septembre 2026)  
> **Auteurs du brouillon :** B. Sipos (JHU/APL), J. Deaton (SAIC)  
> **Groupe de travail IETF :** Delay-Tolerant Networking (DTN WG)  
> **Auteurs des retours :** Équipe de Recherche DTN & Systèmes Maillés Ad-Hoc  
> **Contexte de référence :** Projet *DTN Mesh Algorithm* (Articles 0 à 9) et spécifications CDDL associées (`mesh-algo-extension-block.cddl`, `prophet.cddl`, `maxprop.cddl`, `reticulum.cddl`, `babel.cddl`, `cgr.cddl`).

---

## 1. Synthèse Générale et Alignement Architectural

Le brouillon `draft-ietf-dtn-bp-sand-04` comble un manque historique majeur de l'architecture Bundle Protocol : l'absence d'un protocole standardisé, sécurisé par BPSec, de découverte de voisinage et d'échange de paramètres de convergence layer (CL) au-dessus du plan de données BPv7.

Comme souligné dans la [Section 6.2 de notre Article 9](./article-9-synthese-architecture.md#62-draft-ietf-dtn-bp-sand-secure-advertisement-and-neighborhood-discovery), la vision de SAND est en résonance directe avec nos travaux :
1. **Séparation nette entre le transport de données et la signalisation :** Les bundles de données circulent au format standard BPv7 ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html)), tandis que la signalisation de voisinage s'opère par des bundles dédiés de contrôle.
2. **Modélisation en bases d'information structurées :** Les tables *Local Node*, *Neighbor* et *Network Information Bases* de SAND fournissent exactement la matière première injectée dans le contexte d'évaluation (`input.contact`, `input.neighbors`, `input.uln`) de nos politiques déclaratives Open Policy Agent (OPA).
3. **Format pivot CBOR extensible :** L'usage de CBOR typé et validé par CDDL ([RFC 8610](https://www.rfc-editor.org/rfc/rfc8610.html)).

Cependant, l'analyse approfondie de la version 04 à la lumière de nos modélisations CDDL et de l'expérimentation de 8 algorithmes de routage hétérogènes (APRS, Spray & Wait, Meshtastic, PRoPHET, MaxProp, Reticulum, Babel, CGR/SABR, GeoDTN) révèle **deux erratas formels dans la spécification CDDL/texte**, ainsi que **plusieurs opportunités d'amélioration architecturale** pour renforcer l'universalité du protocole, notamment sur les réseaux contraints et les topologies tolérantes aux délais.

---

## 2. Erratas Formels et Corrections de Syntaxe CDDL

### 2.1. Erratum Critique : Type de Message Erroné dans la CDDL de `Router Advertisement` (Figure 21)

* **Localisation :** Section 5.7, Figure 21 (ligne 3093 du brouillon).
* **Texte actuel :**
  ```cddl
  $sand-msg /= sand-msg-gen<1, {+ $$router-grp }>
  ```
* **Problème :**  
  Dans le corps de la Section 5.7 (ligne 3044), il est explicitement spécifié :
  > *"The Router Advertisement message SHALL be identified by message type 6."*  
  De même, la Table 16 (Section 9.3.1) attribue le code point `6` à `Router Advertisement` et le code point `1` à `Data Solicitation`.  
  Dans la Figure 21, l'instanciation du générique utilise `<1, ...>` au lieu de `<6, ...>`, ce qui écrase ou entre en collision avec la définition de `Data Solicitation` (Figure 5).
* **Correction recommandée :**
  ```cddl
  $sand-msg /= sand-msg-gen<6, {+ $$router-grp }>
  ```

---

### 2.2. Erratum Textuel : Numérotation des Bits de Sécurité d'Endpoint (Section 5.8)

* **Localisation :** Section 5.8, paragraphes décrivant `Payload Security Required` (lignes 3160-3165 du brouillon).
* **Texte actuel :**
  > *"The security flag at bit 0 indicates that the payload SHALL be a target of a BIB that the node can accept.  
  > The security flag at **bit 1** indicates that the payload SHALL be a target of a BCB that the node can accept.  
  > The security flag at **bit 1** indicates that the any accepted security block SHALL bind to the primary block as AAD."*
* **Problème :**  
  Le texte mentionne deux fois consécutives le bit 1. En examinant la CDDL de la Figure 22 (lignes 3180-3184) :
  ```cddl
  endpoint-sec-flags = &(
      need-bib: 0,
      need-bcb: 1,
      bind-primary: 2,
  )
  ```
  Le flag `bind-primary` est assigné à l'index de bit `2`.
* **Correction recommandée :**
  Remplacer la troisième phrase par :
  > *"The security flag at **bit 2** indicates that any accepted security block SHALL bind to the primary block as AAD."*

---

### 2.3. Cohérence CDDL : Séparateur Manquant dans `sand-msg-gen` (Figure 3)

* **Localisation :** Section 5, Figure 3 (lignes 1808-1815 du brouillon).
* **Texte actuel :**
  ```cddl
  sand-msg-gen<type-id, data-map> = [
      msg-type: type-id
      msg-meta: {
          * $$msg-meta-grp,
          * priv16 => any
      },
      + msg-data: data-map
  ]
  ```
* **Problème :**  
  Il manque une virgule après `msg-type: type-id` à la ligne 1809. Bien que certains parseurs CDDL tolèrent l'absence de virgule en fin de ligne, la RFC 8610 préconise l'usage strict de la virgule pour délimiter les éléments d'un tableau CBOR.
* **Correction recommandée :**
  ```cddl
  sand-msg-gen<type-id, data-map> = [
      msg-type: type-id,
      msg-meta: {
          * $$msg-meta-grp,
          * priv16 => any
      },
      + msg-data: data-map
  ]
  ```

---

## 3. Extension du Registre IANA "SAND Routing Types" (Table 25)

### 3.1. Constat : Une Monoculture de SABR/CGR

Dans `draft-ietf-dtn-bp-sand-04`, la Table 25 (Section 9.3.6) n'enregistre qu'un seul algorithme de routage :
* Code `1` : **SABR** (*Schedule-Aware Bundle Routing*, CCSDS / RFC 8877).

SABR/CGR est parfaitement adapté aux réseaux orbitaux déterministes. Toutefois, le champ d'application de BPv7 s'étend largement aux réseaux ad-hoc terrestres, tactiques, maritimes, véhiculaires et d'urgence, où la topologie est **opportuniste, probabiliste ou maillée sans calendrier préétabli**.

Laisser tous les autres paradigmes de routage dans la plage d'expérimentation privée (`-32768 à -1`) priverait la communauté DTN de l'interopérabilité offerte par SAND pour ces algorithmes.

### 3.2. Proposition d'Allocations Standardisées et Modélisation CDDL

Nous recommandons d'allouer formellement dans la Table 25 et de typer dans la Table 26 les familles algorithmiques majeures suivantes, validées dans nos spécifications CDDL :

| Code Proposé | Nom | Paradigme & Référence | Métriques Associées Requises |
| :--- | :--- | :--- | :--- |
| **1** | `SABR` | Déterministe temporel (existant) | Datarate, Delay (OWLT), BER (Figure 20) |
| **2** | `PROPHET` | Probabiliste opportuniste ([RFC 6693](https://www.rfc-editor.org/rfc/rfc6693.html)) | Prévisibilité de livraison $P(A, B)$, matrice de transductivité, fréquence d'encounters |
| **3** | `MAXPROP` | Probabiliste & Ordonnancement | Vecteur de probabilité normalisé, coût d'information log $-\log(P + \epsilon)$ |
| **4** | `BABEL-MESH`| Vecteur de distance réactif sans boucle ([RFC 8966](https://www.rfc-editor.org/rfc/rfc8966.html)) | Coût bidirectionnel 2-way (rxcost/txcost), Router-ID, Seqno anti-boucle |
| **5** | `RETICULUM` | Vecteur de distance cryptographique | Announce Hops, Path MTU, Destination Hash (128 bits) |
| **6** | `GEODTN` | Géographique / Geocasting | Coordonnées géodésiques WGS-84, rayon de couverture, vecteur cinématique |

#### Extension CDDL Recommandée pour `nbr-metrics`

```cddl
; Extension des métriques de routage pour bp-sand
$nbr-metrics /= {
    nbr-metrics-base<2>, ; PRoPHET (RFC 6693)
    nbr-rtm-prophet-p-value,
    ? nbr-rtm-prophet-aging-factor
}

$nbr-metrics /= {
    nbr-metrics-base<3>, ; MaxProp
    nbr-rtm-maxprop-cost,
    ? nbr-rtm-maxprop-hop-penalty
}

$nbr-metrics /= {
    nbr-metrics-base<4>, ; Babel MANET / AREDN
    nbr-rtm-babel-rx-cost,
    nbr-rtm-babel-tx-cost,
    nbr-rtm-babel-seqno
}

$nbr-metrics /= {
    nbr-metrics-base<6>, ; GeoDTN
    nbr-rtm-geo-latitude,
    nbr-rtm-geo-longitude,
    ? nbr-rtm-geo-altitude,
    ? nbr-rtm-geo-radius-meters
}

; Définitions des types associés
nbr-rtm-prophet-p-value = (-1: float .within (0.0 .. 1.0))
nbr-rtm-prophet-aging-factor = (-2: float)
nbr-rtm-maxprop-cost = (-1: float)
nbr-rtm-maxprop-hop-penalty = (-2: uint)
nbr-rtm-babel-rx-cost = (-1: uint)
nbr-rtm-babel-tx-cost = (-2: uint)
nbr-rtm-babel-seqno = (-3: uint)
nbr-rtm-geo-latitude = (-1: float .within (-90.0 .. 90.0))
nbr-rtm-geo-longitude = (-2: float .within (-180.0 .. 180.0))
nbr-rtm-geo-altitude = (-3: float)
nbr-rtm-geo-radius-meters = (-4: uint)
```

---

## 4. Télémétrie de Nœud : Buffer Occupancy et Pression Mémoire

### 4.1. Lacune dans `Resource Advertisement` (Section 5.5, Table 22)

Actuellement, le message de type 4 (`Resource Advertisement`) ne définit qu'un seul paramètre :
* Clé `1` : `Operating Schedule` (calendrier on/off de disponibilité).

Or, dans un réseau tolérant aux délais reposant sur le paradigme *Store-Carry-and-Forward*, la contrainte la plus immédiate à laquelle fait face un nœud mobile n'est pas uniquement son alimentation électrique, mais sa **capacité mémoire disponible (buffer space / storage capacity)**.

Lorsqu'un nœud évalue l'opportunité de transférer un bundle vers un voisin :
* Si le buffer du voisin est saturé (> 90%), le transfert risque de provoquer un rejet immédiat (`drop-head` ou rejet au CLA).
* Dans des algorithmes avancés comme MaxProp ou HP-MaxProp ([Article 4](./article-4-maxprop.md)), la gestion des files d'attente d'éviction dépend directement du volume mémoire restant.

### 4.2. Recommandation

Ajouter à la Table 22 ("SAND Resource Parameters") les métriques de stockage suivantes :

| Clé | Paramètre | Type CBOR | Description |
| :--- | :--- | :--- | :--- |
| **2** | `Total Storage Capacity` | `uint` | Volume total du stockage persistant alloué à BP en octets. |
| **3** | `Available Storage Space` | `uint` | Espace disponible en octets pour accueillir de nouveaux bundles. |
| **4** | `Storage Pressure State` | `uint` | Enumération d'état de congestion : `NORMAL (0)`, `WARNING (1)`, `CRITICAL (2)`. |

```cddl
; Enrichissement du Resource Advertisement CDDL
$$resource-grp //= (
    ? 2: total-storage-bytes,
    ? 3: free-storage-bytes,
    ? 4: storage-pressure-level
)
total-storage-bytes = uint
free-storage-bytes = uint
storage-pressure-level = &(
    pressure-normal: 0,
    pressure-warning: 1,
    pressure-critical: 2
)
```

---

## 5. Gestion du Buffer DTN : Summary Vectors et Cleared Lists

### 5.1. Le Problème du "Contact Éphémère"

La Section 1.2 de SAND détaille la découverte de voisins, de portée et de topologie locale (1-hop et 2-hop). Cependant, dès qu'un contact est validé entre deux nœuds DTN, la première opération opérationnelle requise consiste à **synchroniser les données utiles** :
1. **Éviter le transfert redondant de bundles déjà possédés :** Déterminer l'intersection des inventaires de bundles.
2. **Purge collective des tampons :** Informer le voisin des bundles qui ont déjà été livrés à leur destination finale pour libérer la mémoire (mécanisme *Cleared List* de MaxProp ou *Delivery ACKs* de PRoPHET).

À ce jour, SAND ne couvre pas ces aspects et renvoie implicitement à d'autres protocoles.

### 5.2. Articulation avec BPQ ou Extension Dédiée

Deux approches sont envisageables pour le groupe de travail IETF :

1. **Option A (Clarification de portée dans la Section 2.2) :**  
   Documenter explicitement l'articulation entre SAND et les mécanismes de requête de bundle comme **BPQ** (*Bundle Protocol Query Extension Block* - `draft-cruickshank-dtnrg-bundle-query`) ou les échanges de *Summary Vectors* applicatifs. Préciser que SAND s'arrête à la découverte de nœuds/liens et que la synchronisation d'inventaire de buffer s'exécute au-dessus.
2. **Option B (Intégration d'un sous-type de message de contrôle d'inventaire) :**  
   Comme démontré dans notre architecture réconciliée (Section 3 de l'[Article 9](./article-9-synthese-architecture.md)), l'ajout de deux types de messages légers permet de transformer SAND en un plan de signalisation DTN complet :
   * `Inventory Summary` (Type de message `9`) : échange des condensats canoniques `(Source EID, Creation Time, Sequence)` ou d'un filtre de Bloom.
   * `Purge Acknowledgement` (Type de message `10`) : liste des Bundle IDs livrés pour éviction collective.

---

## 6. Liaisons Asymétriques et Validation de Qualité de Canal (Mécanisme IHU)

### 6.1. Limite du Modèle d'État `HEARD / SYMMETRIC / LOST`

Dans la Section 5.6 (Figure 18), SAND adopte le modèle de portée de MANET NHDP ([RFC 6130](https://www.rfc-editor.org/rfc/rfc6130.html)) :
* `HEARD (1)` : Le nœud local a reçu un message du voisin.
* `SYMMETRIC (2)` : Le nœud local apparaît dans le message de topologie du voisin.
* `LOST (3)` : Expiration du timeout.

Sur des canaux radio contraints (HF, VHF, LoRa, optique spatiale), la propagation est quasi systématiquement **asymétrique** en raison des écarts de puissance d'émission, des gains d'antenne, des interférences locales et des niveaux de bruit ambiant :
* Le nœud A peut décoder le paquet Hello de B (qui émet à 1 Watt avec une antenne directionnelle).
* Mais B peut être incapable d'entendre les bundles de données de A (qui émet à 100 mW avec une antenne omnidirectionnelle).

Déclarer la liaison `SYMMETRIC` sur la simple présence d'un ID de nœud est insuffisant pour garantir la fiabilité du transport de données BPv7.

### 6.2. Recommandation : Rapport de Qualité Reçue (Inspiration Babel IHU)

Dans Babel ([RFC 8966](https://www.rfc-editor.org/rfc/rfc8966.html)) et notre spécification [`babel.cddl`](./babel.cddl), le message `IHU` (*I Heard You*) transporte la métrique de réception (`rx-cost`), permettant au pair de calculer un coût de chemin bidirectionnel réaliste.

Nous recommandons d'ajouter dans `Local Topology Advertisement` (Figure 18 / Table 23) un paramètre optionnel de télémétrie de signal reçu :

```cddl
; Enrichissement du Local Topology Advertisement CDDL
$$localtopo-grp //= (
    ? 3: link-signal-quality
)

link-signal-quality = {
    ? 1: rx-snr-db: float,         ; Rapport signal/bruit mesuré en dB
    ? 2: rx-rssi-dbm: float,       ; Puissance reçue en dBm
    ? 3: packet-loss-rate: float   ; Taux de perte estimé [0.0 .. 1.0]
}
```

---

## 7. Prise en Compte des Convergence Layers Non-IP et Contraintes Radio

### 7.1. Biais IP et Ethernet dans le Registre "SAND CL Types" (Table 20)

Dans la Table 20 (Section 9.3.4), les types de couches de convergence alloués sont exclusivement :
* Code `1` : TCPCLv4 ([RFC 9174](https://www.rfc-editor.org/rfc/rfc9174.html))
* Code `2` : UDPCLv2
* Code `3, 252, 253` : Variantes LTPCL over UDP
* Code `4` : BTP-U Over Ethernet
* Code `254` : TCPCLv3
* Code `255` : UDPCL expérimental

Aucune couche de convergence **non-IP, radio ou faible débit** n'est répertoriée, alors même que la Section 1.1 revendique l'indépendance de SAND vis-à-vis des couches sous-jacentes.

Sur les théâtres d'opérations d'urgence, de secours citoyen ou d'exploration où BPv7 est déployé, plusieurs CLAs non-IP jouent un rôle capital :
1. **LoRa CLA :** Transmission asynchrone par paquets sur bandes ISM (868/915 MHz).
2. **AX.25 / FX.25 CLA :** Réseaux radioamateurs packet et APRS sur VHF/UHF ([Article 1](./article-1-aprs.md)).
3. **BLE (Bluetooth Low Energy) CLA :** Échanges opportunistes direct smartphone-à-smartphone (*Pocket Switched Networks*).
4. **Serial / Slip / KISS CLA :** Liaisons série physiques filaires point-à-point ou modems satellite directs.

### 7.2. Recommandation

Réserver formellement des points de code dans la Table 20 pour ces CLAs et spécifier leurs paramètres d'attachement minimaux :

| Code Recommandé | Nom CL | Paramètres Spécifiques Typés Recommandés |
| :--- | :--- | :--- |
| **5** | `LORA-CLA` | Fréquence (Hz), Spreading Factor (7-12), Bandwidth (kHz), Coding Rate |
| **6** | `AX25-CLA` | Call-sign émetteur (SSID), Baudrate (1200/9600 AFSK), TNC port |
| **7** | `BLE-CLA` | Service UUID 128-bit, MAC BLE, Advertising Interval |

---

## 8. Surcoût Protocolaire et Profil Allégé pour Liens Faible Débit

### 8.1. Analyse du Budget d'Octets sur Liens Contraints

La Section 4.4 de SAND impose l'usage strict de BPSec ([RFC 9172](https://www.rfc-editor.org/rfc/rfc9172.html)) :
> *"All SAND Bundles SHALL contain a Block Integrity Block (BIB) which targets the payload block... This document does not allow for an insecure use of SAND."*

Par ailleurs, la structure d'encapsulation de l'ADU (Section 4.2) impose un tableau CBOR où chaque message SAND est enveloppé dans un `bstr` individuel :
```cddl
sand-adu-seq = [ version: 1, + adu-item ]
adu-item = bstr .cborseq sand-msg
```

Calculons le surcoût minimal d'un bundle SAND Hello sur une interface LoRa (MTU physique maximale de 222 octets à SF7, ou seulement 51 octets à SF12) :
* Bloc Primary BPv7 : ~30 octets
* Bloc Hop Count (obligatoire selon Section 4.2) : ~10 octets
* Bloc BIB BPSec (Target, Security Source, Context, Signature ECDSA P-256 ou Ed25519) : ~80 à 100 octets
* Payload Block Wrapper : ~5 octets
* ADU Sequence (`version` + double encapsulation `bstr`) : ~10 octets
* Message SAND Hello (Metadata + ULN + CL + Topo) : ~80 à 150 octets
* **Total estimé : 205 à 305 octets !**

Sur un lien LoRa à Spreading Factor élevé (SF11 ou SF12) ou sur une liaison HF à 300 bauds, **un tel bundle excède la MTU de trame physique sans fragmentation et sature le temps de parole légal (1% duty cycle en Europe, soit 36 secondes d'émission par heure)**.

### 8.2. Recommandations pour un Profil Compact (*Constrained Profile*)

1. **Assouplissement de la double encapsulation `bstr` :**  
   Permettre pour les profils contraints d'omettre l'encapsulation `bstr` intermédiaire par message lorsque le bundle ne subit pas de fragmentation applicative, économisant les octets de préfixe de longueur CBOR.
2. **Usage de condensats cryptographiques tronqués (Style Reticulum) :**  
   Permettre l'authentification de signature ou de clé par des hashs tronqués de 16 octets plutôt que par des certificats X.509 complets ou des chaînes intermédiaires.
3. **Politique d'émission événementielle et Jitter exponentiel :**  
   Dans la Section 6.1 (`Group Hello`), insister fortement sur la suppression d'émission : **ne jamais réémettre de Hello périodique si l'état topologique local n'a subi aucune modification**, et appliquer un algorithme de type *Trickle Timer* ([RFC 6206](https://www.rfc-editor.org/rfc/rfc6206.html)) pour espacer exponentiellement les annonces en régime stationnaire.

---

## 9. Prise en Compte de la Géolocalisation pour le Geocasting (GeoDTN)

Dans de nombreux scénarios humanitaires et d'urgence (Search and Rescue, feux de forêt, voir notre [Article 8](./article-8-geodtn.md)), les nœuds se déplacent sur le terrain sans connectivité infrastructurelle. L'acheminement des messages repose alors sur la proximité spatiale :
* Routage géographique MFR (*Most Forward within Radius*).
* Geocasting vers une zone de sinistre polygonale ou circulaire.

Actuellement, aucune Information Base de SAND (ni `Local Node`, ni `Neighbor`, ni `Local Topology`) ne prévoit de champ pour les **coordonnées géographiques**.

Nous suggérons d'intégrer dans les paramètres de topologie ou de ressource un tuple de positionnement optionnel (Latitude, Longitude, Altitude, Précision) conforme au standard CBOR Tag pour coordonnées géographiques ([RFC 9179](https://www.rfc-editor.org/rfc/rfc9179.html)) ou encodé en flottants compacts.

---

## 10. Découplage Architectural et Moteur de Politiques Déclaratif (OPA / Rego)

Dans l'ensemble du brouillon (notamment Sections 6.3, 7.3, 7.5 et 8.5), de nombreuses décisions fondamentales sont laissées à la discrétion de l'implémentation sous la mention :
> *"The means by which an entity does this is implementation specific."*

Cela concerne :
* L'autorisation ou le refus d'enrôler un voisin découvert (Section 7.5).
* Le filtrage contextuel des annonces selon la sensibilité du sous-réseau (Section 7.3).
* La sélection du prochain saut CLA pour l'acheminement effectif des bundles.

Notre retour d'expérience architectural (Articles 0 à 9) démontre que coder ces règles en dur dans le démon de transport (en C, C++ ou Rust) fragilise les déploiements et empêche toute reconfiguration à chaud sur le terrain.

Nous suggérons d'inclure dans la Section 7 (*Operational Considerations*) une **note architecturale recommandant le découplage entre l'entité SAND et un moteur d'arbitrage de politiques déclaratif (type OPA / Rego)** :
* L'entité SAND maintient les *Information Bases* (Section 3) et les projette sous forme structurée (JSON/CBOR).
* Un moteur de règles indépendant évalue les autorisations de voisinage et les filtrages d'annonces de manière auditable et modifiable à chaud sans redémarrage du service de transport DTN.

---

## 11. Tableau Récapitulatif des Recommandations

| Réf. | Section du Draft | Nature | Niveau d'Urgence | Résumé de l'Action Proposée |
| :--- | :--- | :--- | :--- | :--- |
| **ERR-1** | Section 5.7, Fig. 21 | **Bug CDDL** | 🔴 **Critique** | Remplacer `sand-msg-gen<1, ...>` par `sand-msg-gen<6, ...>`. |
| **ERR-2** | Section 5.8 (texte) | **Bug Texte** | 🟠 **Majeur** | Corriger le flag `bind-primary` au **bit 2** au lieu du bit 1. |
| **ERR-3** | Section 5, Fig. 3 | **Syntaxe CDDL**| 🟡 Mineur | Ajouter la virgule manquante après `msg-type: type-id,`. |
| **REC-1** | Section 9.3.6, Tab. 25 | Extension IANA | 🟢 Recommandé | Étendre les Routing Types à PRoPHET, MaxProp, Babel, Reticulum, GeoDTN. |
| **REC-2** | Section 5.5, Tab. 22 | Télémétrie | 🟢 Recommandé | Ajouter les métriques de stockage disponible et pression mémoire. |
| **REC-3** | Section 5.6, Tab. 23 | Métrique lien | 🟢 Recommandé | Ajouter la qualité reçue (SNR/RSSI) pour détecter les asymétries radio (IHU). |
| **REC-4** | Section 9.3.4, Tab. 20 | Support CLA | 🟢 Recommandé | Réserver des identifiants CL pour les liaisons radio non-IP (LoRa, AX.25, BLE). |
| **REC-5** | Section 4.2 / 4.4 | Optimisation | 🟢 Recommandé | Documenter un profil compact pour réseaux LPWAN / canaux sévèrement contraints. |
| **REC-6** | Section 7.5 | Architecture | 🔵 Informatif | Recommander un modèle d'arbitrage découplé par moteur de politiques (ex: OPA). |

---

> Ces retours visent à consolider le brouillon `draft-ietf-dtn-bp-sand` afin d'en faire le socle de convergence universel pour tous les réseaux tolérants aux délais et maillés opportunistes de nouvelle génération.
