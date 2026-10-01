# Architectural Study: DTN Routing & Opportunistic Policies with OPA

Welcome to the documentation portal for the architectural study and formal specification of transposing opportunistic and mesh routing algorithms to **Bundle Protocol v7 (BPv7 - RFC 9171)** using **Open Policy Agent (OPA)** declarative policies and **CDDL (RFC 8610)** schema language.

> 📖 **Project GitHub Repository:** [github.com/loic-fejoz/dtn-mesh-algorithms](https://github.com/loic-fejoz/dtn-mesh-algorithms)

> ℹ️ **Editorial Transparency Note (EU AI Act Alignment):** This article was generated with AI assistance under the editorial direction and structuring of a human author, who assumes responsibility for its technical review, verification, and content (ongoing proofreading).

---

## 🚀 Purpose and Paradigm

Delay & Disruption Tolerant Networks (DTN) and Mobile Ad-Hoc Mesh Networks (MANET) share the challenge of delivering messages in constrained, intermittently connected environments.

This study introduce step by step the usual routing algorithms used in mesh network. It also demonstrates that the **routing policy can be entirely decoupled from the host forwarding engine** by delegating Ingress, Egress (Contact CLA), and Buffer Storage decisions to declarative Rego rules evaluated dynamically by Open Policy Agent (OPA).

```
 +-------------------------------------------------------------------+
 |                     Declarative Control Plane                     |
 |        OPA / Rego Policies (Ingress, Egress Contact, Storage)     |
 +-------------------------------------------------------------------+
                                   │ Rego Rule Evaluation
                                   ▼
 +-------------------------------------------------------------------+
 |                        Host Data Plane                            |
 |         BPv7 Engine (Hardy, uDTN, IBR-DTN, ION, HDTN)            |
 +-------------------------------------------------------------------+
```

---

## 📚 Article Series Summary

| Article | Title & Description |
| :--- | :--- |
| **[Article 0 — Foundations](./article-0-intro.en.md)** | Architectural principles, control/data plane decoupling, and OPA integration into BPv7. |
| **[Article 1 — APRS Digipeating](./article-1-aprs.en.md)** | Transposing amateur radio AX.25 WIDE n-N digipeating to BPv7. |
| **[Article 2 — Flooding & Spray and Wait](./article-2-flood.en.md)** | Economical flooding, binary/source replication control, and Meshtastic channel management. |
| **[Article 3 — PRoPHET v2](./article-3-prophet.en.md)** | Probabilistic routing via encounter history (RFC 6693), transitivity, and aging. |
| **[Article 4 — MaxProp & HP-MaxProp](./article-4-maxprop.en.md)** | Logarithmic Dijkstra cost, fluid queue sorting, and distributed Cleared List. |
| **[Article 5 — Reticulum Stack (RNS)](./article-5-reticulum.en.md)** | 128-bit cryptographic addressing, Ed25519 signed announces, and path discovery. |
| **[Article 6 — Babel & AREDN](./article-6-babel-aredn.en.md)** | Proactive Bellman-Ford distance vector (RFC 8966), Feasible Distance, and HYMAD gateway. |
| **[Article 7 — Contact Graph Routing (CGR)](./article-7-cgr.en.md)** | Deterministic space routing via contact schedules (CCSDS 734.3-B-1) and OWLT. |
| **[Article 8 — GeoDTN](./article-8-geodtn.en.md)** | Greedy/perimeter geographic routing (GPSR) and spatially bounded dissemination (Geocast). |
| **[Article 9 — Synthesis & Architecture](./article-9-synthese-architecture.en.md)** | Comparative matrix, OPA benchmark, security risk analysis, and OTA deployment plan. |

---

## 🛠️ CDDL Specifications & Rego Policies

- **Unified DTN Extension Block**: CDDL Spec [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl)
- **OPA Rego Policies**: [policies/ directory](./policies/) (140/140 PASS)
- **Protocol Specifications**: [babel.cddl](./babel.cddl), [cgr.cddl](./cgr.cddl), [maxprop.cddl](./maxprop.cddl), [prophet.cddl](./prophet.cddl), [reticulum.cddl](./reticulum.cddl)
