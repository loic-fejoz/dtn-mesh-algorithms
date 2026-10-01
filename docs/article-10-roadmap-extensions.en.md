# Article 10 — Perspectives and Extension Roadmap: Towards a Panoramic View of DTN Routing and Control Plane Evolution

> **CDDL Specifications:** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl), [prophet.cddl](./prophet.cddl), [maxprop.cddl](./maxprop.cddl), [reticulum.cddl](./reticulum.cddl), [babel.cddl](./babel.cddl), [cgr.cddl](./cgr.cddl)

> ℹ️ **Editorial Transparency Note (EU AI Act Alignment):** This article was generated with AI assistance under the editorial direction and structuring of a human author, who assumes responsibility for its technical review, verification, and content (ongoing proofreading).

---

## 1. Introduction: Completing the Panoramic View of DTN Routing

Through Articles 0 to 9, this project has demonstrated that it is possible to formalize, transpose, and execute a wide spectrum of opportunistic and mesh routing algorithms on top of **Bundle Protocol version 7 (BPv7 - RFC 9171)** using the **Open Policy Agent (OPA)** declarative policy engine.

However, scientific literature on **Delay- and Disruption-Tolerant Networks (DTNs)** is immensely rich. As shown by seminal survey papers (notably **Modi & Singh 2017**, the survey on social DTN routing by **Jain & Soares 2021**, synthesis work from the **IETF DTN WG**, and **Wikipedia DTN Routing** classifications), operational DTN environments span diverse use cases:
- Satellite constellations and deep-space probes (*Contact Graph Routing / CGR*).
- Tactical ad-hoc and mesh networks (*Babel, Reticulum, APRS*).
- Urban vehicular networks (*VANET, GeoMob, DAWN*).
- Human-carried social networks (*Pocket Switched Networks / PSN, Bubble Rap, SimBet*).
- Underwater or environmental sensor networks (*UWSN, Q-Learning, LMS Filters*).

The objective of this **Article 10** is twofold:
1. Provide a **complete 360° panoramic view** of all DTN routing algorithm families identified in literature, mapping what is covered by our reference implementation against future extension targets.
2. Demonstrate that the **Control Plane** must never be designed as a rigid or monolithic schema, but as an **extensible grammar** (defined in CDDL and JSON Schema) capable of dynamically accommodating new telemetries without breaking backward compatibility over constrained radio links.

---

## 2. Panoramic Mapping and Gap Analysis

The table below summarizes all DTN routing families identified in literature and their mapping to the *DTN Mesh Algorithm* architecture:

| Routing Family | Representative Protocols in Literature | Coverage Status in Repository | Associated CDDL Specifications & Rego Policies |
| :--- | :--- | :--- | :--- |
| **1. BOUNDED / UNBOUNDED Flooding & Replication** | Epidemic, Spray & Wait, APRS Digipeating WIDE n-N, Meshtastic | **100% Covered** | [article-1-aprs.en.md](./article-1-aprs.en.md), [article-2-flood.en.md](./article-2-flood.en.md)<br>`policies/aprs/`, `policies/flood/` |
| **2. Probabilistic & Encounter History** | PRoPHET (RFC 6693), MaxProp, HP-MaxProp, RAPID | **100% Covered** | [article-3-prophet.en.md](./article-3-prophet.en.md), [article-4-maxprop.en.md](./article-4-maxprop.en.md)<br>`prophet.cddl`, `maxprop.cddl`, `policies/prophet/`, `policies/maxprop/` |
| **3. Distance Vector & MANET-DTN Hybrid** | Reticulum (RNS), Babel (RFC 8966), AREDN, HYMAD | **100% Covered** | [article-5-reticulum.en.md](./article-5-reticulum.en.md), [article-6-babel-aredn.en.md](./article-6-babel-aredn.en.md)<br>`reticulum.cddl`, `babel.cddl`, `policies/reticulum/`, `policies/babel/` |
| **4. Deterministic & Spatial (Scheduled Contacts)** | Contact Graph Routing (CGR / SABR - CCSDS 734.3-B-1) | **100% Covered** | [article-7-cgr.en.md](./article-7-cgr.en.md)<br>`cgr.cddl`, `policies/cgr/` |
| **5. Geographic & Kinematic** | GeoDTN (Greedy/Perimeter), Geocasting, CaD (Converge-and-Diverge), GeoMob | **Family Covered** *(Kinematic extensibility proposed in Section 3)* | [article-8-geodtn.en.md](./article-8-geodtn.en.md)<br>`policies/geodtn/`, `mesh-algo-extension-block.cddl` |
| **6. Social & Community Routing** | Bubble Rap, SimBet, Label Routing, SOSIM, SEBAR, EpSoc, HiBOp | **Family Covered via Utility Metrics** *(Support for $k$-clique graphs proposed in Section 3)* | Utility primitives in `policies/maxprop/` and `policies/prophet/` |
| **7. Density, Channel & Storage Aware** | GSTAR (Storage Aware), DAWN (Density Adaptive with Deadline) | **Family Covered** *(Channel load & storage metrics formalized in Section 3)* | `policies/storage.rego`, `prophet.cddl` (`available-storage-bytes`) |
| **8. Adaptive Routing & Machine Learning** | LMS Filters, Q-Learning for underwater DTNs (UWSN) | **Future Perspectives** *(Roadmap Phase 3)* | Exponential predictability in PRoPHET |
| **9. Spatio-Temporal Link State & Non-Cooperative** | DTLSR (DTN Link State), Game Theory Routing (Incentives / Tokens / Reputation) | **Future Perspectives** *(Roadmap Phase 3)* | Deduplication and `blacklist_sources` filters in `policies/ingress.rego` |

---

## 3. Demonstrating Control Plane Extensibility

One of the key takeaways of our work is the **strict separation between the Wire Format and OPA's Policy Evaluation Input**.

### A. Principle of CDDL Extensibility

To avoid overloading constrained radio links (LoRa, VHF/AX.25, HF), wire-format signaling (Extension Block Type 200) carries only minimal intention primitives. In contrast, local modem measurements (SNR, RSSI), node health (battery, buffer occupation), and neighbor telemetry are injected into the local control plane as extensible CBOR/JSON maps via optional keys (`? key => type`).

Here is how the [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl) specification naturally expands to accommodate new requirements identified in research literature:

```cddl
; ==============================================================================
; EXTENSION OF OPA EVALUATION CONTEXT (input) FOR NEW ALGORITHM FAMILIES
; ==============================================================================

policy-evaluation-input = {
    bundle: bundle-context,
    node: local-node-context,
    current_dtn_time_ms: uint,
    ? ingress: ingress-telemetry-context,
    ? contact: contact-opportunity-context,
    ? social: social-network-context,          ; [NEW] Social Routing Extension
    ? kinematics: node-kinematics-context,      ; [NEW] Kinematic / GeoMob Extension
    ? channel: channel-capacity-context         ; [NEW] Density & Channel DAWN Extension
}

; ------------------------------------------------------------------------------
; 1. SOCIAL ROUTING EXTENSION (Bubble Rap, SimBet, SOSIM, SEBAR)
; ------------------------------------------------------------------------------
social-network-context = {
    ? local_community_id: tstr,                 ; Local k-clique cluster identifier
    ? labels: [* tstr],                         ; Set of social labels
    ? degree_centrality: float,                ; Degree centrality (unique contacts count)
    ? betweenness_centrality: float,           ; Betweenness centrality (bridge between communities)
    ? interest_profile_hash: bytes .size 16,    ; Hash of interest profile (SOSIM)
    ? peer_social_metrics: { * tstr => {        ; Social metrics received from neighbors
        community_id: tstr,
        betweenness: float,
        degree: float
    }}
}

; ------------------------------------------------------------------------------
; 2. ADVANCED KINEMATIC & GEOGRAPHIC EXTENSION (CaD, GeoMob, VANET)
; ------------------------------------------------------------------------------
node-kinematics-context = {
    speed_meters_per_sec: float,                ; Instantaneous scalar speed
    heading_degrees: float .within (0.0 .. 360.0), ; Kinematic heading / direction (0-360°)
    gps_error_meters: float,                    ; GPS measurement uncertainty (HDOP precision)
    ? predicted_trajectory_vector: [float, float] ; Estimated displacement vector (dx/dt, dy/dt)
}

; ------------------------------------------------------------------------------
; 3. NEIGHBORHOOD DENSITY & CHANNEL CAPACITY EXTENSION (DAWN, GSTAR)
; ------------------------------------------------------------------------------
channel-capacity-context = {
    neighbor_density_count: uint,               ; Number of active neighbors in radio range
    channel_duty_cycle_pct: float,              ; Radio channel duty cycle (0 to 100%)
    ambient_rssi_floor_dbm: float,              ; Measured background noise floor
    storage_pressure_state: &(                  ; Buffer pressure state enum
        state-normal: 0,
        state-warning: 1,
        state-critical: 2,
        state-full: 3
    )
}
```

---

## 4. Alignment with IETF Standardization (IETF SAND `draft-ietf-dtn-bp-sand-04`)

To allow signaling information to flow between heterogeneous nodes without proprietary protocols, we recommend expanding the **IETF SAND (Secure Advertisement and Neighborhood Discovery)** specification.

As detailed in our technical proposal document [comments-ietf-dtn-bp-sand-04.md](./comments-ietf-dtn-bp-sand-04.md), the IANA registry `SAND Routing Types` (Table 25) and `nbr-metrics` structures (Table 26) can be extended as follows:

```cddl
; CDDL Extension Proposal for draft-ietf-dtn-bp-sand-04
$sand-routing-types /= &(
    sand-rtm-sabr: 1,       ; CCSDS CGR / SABR (existing)
    sand-rtm-prophet: 2,    ; PRoPHET RFC 6693
    sand-rtm-maxprop: 3,    ; MaxProp
    sand-rtm-babel: 4,      ; Babel MANET / AREDN
    sand-rtm-reticulum: 5,  ; Reticulum Cryptographic Mesh
    sand-rtm-geodtn: 6,     ; GeoDTN & Kinematic Routing
    sand-rtm-social: 7      ; Social-Based Routing (Bubble Rap / SimBet)
)

; Extension of neighbor metrics transmitted in SAND Router Advertisements
$nbr-metrics /= {
    nbr-metrics-base<6>, ; Geographic & Kinematic Metrics (GeoDTN / CaD)
    nbr-rtm-geo-latitude,
    nbr-rtm-geo-longitude,
    ? nbr-rtm-kinematic-speed,
    ? nbr-rtm-kinematic-heading
}

$nbr-metrics /= {
    nbr-metrics-base<7>, ; Social Metrics (Bubble Rap / SimBet)
    nbr-rtm-social-community-id,
    nbr-rtm-social-betweenness,
    nbr-rtm-social-degree
}
```

---

## 5. Step-by-Step Implementation Roadmap

To extend the *DTN Mesh Algorithm* architecture towards full native coverage of the entire scientific landscape, we define a **3-phase roadmap**:

```mermaid
flowchart TD
    subgraph Phase 1: Short Term
        P1A["Kinematic Telemetry (Speed, Heading, GPS Error)"]
        P1B["Channel Load & Density Metrics (DAWN/GSTAR)"]
        P1C["Delivery ACK & Distributed Buffer Purge"]
    end

    subgraph Phase 2: Medium Term
        P2A["Social Routing Extensions (Bubble Rap, SimBet, SOSIM)"]
        P2B["Distributed K-Clique Community Discovery"]
        P2C["Dynamic CGR Contact Plan Distribution via SAND"]
    end

    subgraph Phase 3: Long Term
        P3A["Distributed Reinforcement Learning (Q-Learning / LMS)"]
        P3B["Non-Cooperative Routing via Cryptographic Tokens & Reputation"]
        P3C["Spatio-Temporal LSAs (DTLSR Link-State DTN)"]
    end

    Phase 1 --> Phase 2 --> Phase 3
```

---

## 6. Technical Series Conclusion

With **Article 10**, the technical series of the *DTN Mesh Algorithm* project provides a **complete, rigorous, and forward-looking panoramic view** of routing engineering in delay-tolerant and constrained mesh networks.

By demonstrating that complex algorithms (whether probabilistic like PRoPHET/MaxProp, deterministic like CGR, geometric like GeoDTN, cryptographic like Reticulum, or social like Bubble Rap) express themselves transparently through **declarative OPA policies built on an extensible Control Plane**, this work lays the foundation for next-generation disruption-tolerant telecommunication standards.

---

🏁 **End of the Technical Series.**  
Explore full source code, CDDL specs, declarative policies, and the roadmap in the [DTN Mesh Algorithm Project Repository](./index.md).
