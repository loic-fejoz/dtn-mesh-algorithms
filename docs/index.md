# Étude d'Architecture : Routage DTN & Politiques Opportunistes avec OPA

Bienvenue sur le portail de documentation dédié à l'étude d'architecture et de modélisation de la transposition d'algorithmes de routage opportunistes et maillés vers le **Bundle Protocol v7 (BPv7 - RFC 9171)** via des politiques déclaratives **Open Policy Agent (OPA)** et le langage de schéma **CDDL (RFC 8610)**.

> 📖 **Dépôt GitHub du Projet :** [github.com/loic-fejoz/dtn-mesh-algorithms](https://github.com/loic-fejoz/dtn-mesh-algorithms)

> ℹ️ **Transparence Éditoriale (Conformité EU AI Act) :** Cet article a été rédigé avec l'assistance d'une IA sous la direction éditoriale et la structuration d'un auteur humain, qui en assure la relecture, la vérification technique, et la responsabilité du contenu (relecture en cours).

---

## 🚀 Objectif et Paradigme de l'Étude

Les réseaux tolérants aux interruptions (*Delay & Disruption Tolerant Networking - DTN*) et les réseaux maillés (*Mesh / MANET*) partagent le besoin d'acheminer des messages dans des environnements contraints et partiellement connectés.

Cette étude introduit pas à pas les algorithmes classiques et routage dans les réseaux mesh. Elle démontre aussi qu'il est possible de **découpler totalement la politique d'acheminement du moteur de routage hôte** en confiant les décisions d'Ingress, d'Egress (Contact CLA) et de gestion de stockage à des règles déclaratives évaluables en temps réel par Open Policy Agent (OPA).

```
 +-------------------------------------------------------------------+
 |                    Plan de Contrôle Déclaratif                     |
 |        Politiques OPA / Rego (Ingress, Egress Contact, Storage)   |
 +-------------------------------------------------------------------+
                                   │ Évaluation des règles Rego
                                   ▼
 +-------------------------------------------------------------------+
 |                       Plan de Données Hôte                        |
 |         Moteur BPv7 (Hardy, uDTN, IBR-DTN, ION, HDTN)            |
 +-------------------------------------------------------------------+
```

---

## 📚 Sommaire des Articles de la Série

| Article | Titre & Description |
| :--- | :--- |
| **[Article 0 — Fondations](./article-0-intro.md)** | Principes architecturaux, découplage plan de contrôle/données, et intégration d'OPA dans BPv7. |
| **[Article 1 — Digipeating APRS](./article-1-aprs.md)** | Transposition de l'algorithme radioamateur AX.25 WIDE n-N vers BPv7. |
| **[Article 2 — Flooding & Spray and Wait](./article-2-flood.md)** | Diffusion économe, contrôle de réplication binaire/source, et gestion radio Meshtastic. |
| **[Article 3 — PRoPHET v2](./article-3-prophet.md)** | Routage probabiliste par historique d'rencontres (RFC 6693), calculs de transitivité et d'âge. |
| **[Article 4 — MaxProp & HP-MaxProp](./article-4-maxprop.md)** | Calcul de coût Dijkstra logarithmique, priorisation fluide et Cleared List distribuée. |
| **[Article 5 — Reticulum Stack (RNS)](./article-5-reticulum.md)** | Adressage cryptographique 128-bit, annonces signées Ed25519 et découverte de chemin. |
| **[Article 6 — Babel & AREDN](./article-6-babel-aredn.md)** | Vecteur de distance proactif Bellman-Ford (RFC 8966), Feasible Distance et passerelle HYMAD. |
| **[Article 7 — Contact Graph Routing (CGR)](./article-7-cgr.md)** | Routage spatial déterministe par calendrier de contact (CCSDS 734.3-B-1) et OWLT. |
| **[Article 8 — GeoDTN](./article-8-geodtn.md)** | Routage géographique greedy/perimeter (GPSR) et diffusion spatialement délimitée (Geocast). |
| **[Article 9 — Synthèse & Architecture](./article-9-synthese-architecture.md)** | Matrice comparative, benchmark OPA, sécurité et plan de déploiement Over-The-Air (OTA). |

---

## 🛠️ Spécifications CDDL & Politiques Rego

- **Bloc d'Extension DTN Unifié** : Spécification CDDL [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl)
- **Politiques OPA Rego** : [Répertoire policies/](./policies/) (140/140 tests validés)
- **Spécifications par Protocole** : [babel.cddl](./babel.cddl), [cgr.cddl](./cgr.cddl), [maxprop.cddl](./maxprop.cddl), [prophet.cddl](./prophet.cddl), [reticulum.cddl](./reticulum.cddl)
