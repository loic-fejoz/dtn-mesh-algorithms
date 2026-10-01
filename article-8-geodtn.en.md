# Article 8 — Geographic Routing and Geocasting: GeoDTN and Local Void Traversal under Open Policy Agent

> **Series:** *Transposing Mesh & Opportunistic Routing Algorithms to DTN (BPv7)*  
> **Previous Articles:**  
> - [Article 0 — Foundations of DTN Routing with Open Policy Agent](./article-0-intro.en.md)  
> - [Article 1 — Transposing APRS Digipeating (AX.25 WIDE n-N) to DTN (BPv7)](./article-1-aprs.en.md)  
> - [Article 2 — Taming the Flood in DTN: From Epidemic to Spray and Wait and Meshtastic's Managed Flooding](./article-2-flood.en.md)  
> - [Article 3 — Opportunistic Routing and Encounter History: PRoPHET (RFC 6693) under Open Policy Agent](./article-3-prophet.en.md)  
> - [Article 4 — Probabilistic Routing and Resource-Constrained Buffer Management: MaxProp and its Theoretical Optimizations (HP-MaxProp)](./article-4-maxprop.en.md)  
> - [Article 5 — Hybrid Routing, Distance Vector, and Cryptographic Addressing: Reticulum (RNS) Transposed to DTN](./article-5-reticulum.en.md)  
> - [Article 6 — Proactive Mesh Networks and MANET-DTN Hybrids: AREDN, Babel (RFC 8966), and the HYMAD Architecture under Open Policy Agent](./article-6-babel-aredn.en.md)  
> - [Article 7 — Spatial Deterministic Routing: Contact Graph Routing (CGR / SABR - CCSDS 734.3-B-1) under Open Policy Agent](./article-7-cgr.en.md)  
> **CDDL Specifications:** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl), [prophet.cddl](./prophet.cddl), [maxprop.cddl](./maxprop.cddl), [reticulum.cddl](./reticulum.cddl), [babel.cddl](./babel.cddl) & [cgr.cddl](./cgr.cddl)  
> **Policy Code:** [policies/geodtn/](./policies/geodtn/) ([ingress.rego](./policies/geodtn/ingress.rego), [contact.rego](./policies/geodtn/contact.rego), [storage.rego](./policies/geodtn/storage.rego), [helpers.rego](./policies/geodtn/helpers.rego), [constants.rego](./policies/geodtn/constants.rego), [geodtn_test.rego](./policies/geodtn/geodtn_test.rego))

> ℹ️ **Editorial Transparency Note (EU AI Act Alignment):** This article was generated with AI assistance under the editorial direction and structuring of a human author, who assumes responsibility for its technical review, verification, and content (ongoing proofreading).

---

## 1. The Coordinate as the Sole Address

In the first seven articles of our series, we examined routing under almost every form:
- By forwarding alias ([APRS](./article-1-aprs.en.md)).
- By flooding and physical contention ([Meshtastic & Spray & Wait](./article-2-flood.en.md)).
- By statistical learning of sociability ([PRoPHET](./article-3-prophet.en.md)).
- By probabilistic shortest-path calculation and buffer scheduling ([MaxProp](./article-4-maxprop.en.md)).
- By self-sovereign cryptographic distance vectors ([Reticulum](./article-5-reticulum.en.md)).
- By loop-free proactive radio metrics and island hybridization ([AREDN / Babel](./article-6-babel-aredn.en.md)).
- By deterministic celestial spatio-temporal schedule ([CGR](./article-7-cgr.en.md)).

Now imagine a scenario of a major natural disaster: a large-scale earthquake or a gigantic forest fire.
- Cellular and terrestrial infrastructures are destroyed.
- Hundreds of rescuers, autonomous reconnaissance drones, and victims' distress beacons are active on the ground.
- No central directory exists: **a first responder or drone knows neither the EID nor the IP address of the nearest victim or medical team**.
- The only available information is geographic: "*Forward this medical alert to the disaster zone at coordinates $(45.75^\circ\text{N}, 4.85^\circ\text{E})$, within a 1-kilometer radius*".

This is the domain of **Geographic Routing** and **Targeted Geographic Flooding (Geocasting)**.

---

## 2. The Achilles' Heel of MANETs: The Local Void Trap

In wireless ad-hoc mesh networks (MANETs), the reference geographic algorithm is **GPSR (Greedy Perimeter Stateless Routing)**, formulated by Brad Karp and H. T. Kung (2000).

GPSR relies on an intuitive principle called **Greedy Forwarding**:
> Each node forwards the packet to the physical neighbor that minimizes the Euclidean distance to the destination coordinates.

```
                  The Local Void Trap in MANET
                  =============================

                           [ Geographic Target ]
                                     ^
                                     |
                              (Obstacle / Void)
                                     |
                             [ Relay Node A ]
                                /         \
                               v           v
                         [ Neighbor B ]  [ Neighbor C ]
                  (Further from target than A!)
```

However, greedy routing suffers from a fundamental pitfall: **the local minimum (Local Void)**.
If the carrier node $A$ is closer to the target than all its immediate neighbors (for instance, facing a cliff, a lake, or an uninhabited area with no relays), **the greedy algorithm reaches a dead end**.

In traditional IP/MANET networks:
- GPSR attempts to switch to perimeter routing mode (Perimeter Routing / Face Routing), which consists of traversing the perimeter of the void according to the right-hand rule on a planar graph (RNG or Gabriel Graph).
- In practice (real radio propagation with obstacles, interference, and 3D topology), **planarization fails almost systematically**, causing infinite loops and the pure and simple dropping of packets.

---

## 3. The GeoDTN Breakthrough: Greedy-Carry-and-Forward

Hybridization with **Bundle Protocol v7** sweeps away the fragile complexity of Face Routing with a single stroke:

> **In GeoDTN, a local minimum is not a failure: it is simply a storage opportunity (Carry Phase)!**

When a carrier node $A$ reaches a topological void where no neighbor is closer to the target:
1. The node does not drop the bundle.
2. It does not trigger a perilous planarization algorithm.
3. It keeps the bundle in its DTN storage buffer (**`action: "SKIP"` / Greedy-Carry-and-Forward**).
4. The node physically moves (or waits until a drone, rescue vehicle, or another pedestrian comes within its radio range).
5. As soon as a new contact offers a position closer to the target, greedy mode resumes instantly.

```
       +-------------------------------------------------------------+
       |         Bundle sent to (Target_Lat, Target_Lon)             |
       +-------------------------------------------------------------+
                                      |
                                      v
       +-------------------------------------------------------------+
       |     Does a neighbor closer to target than me exist?         |
       +-------------------------------------------------------------+
                    /                                    \
                [ YES ]                                [ NO ]
                   |                                      |
         Greedy Forwarding                         Local Void Detected
       FORWARD_GREEDY to neighbor                         |
                                                DTN storage active
                                             (Greedy-Carry-and-Forward)
                                             Bundle held in memory
                                                          |
                                             Physical mobility of a node
                                                          |
                                             New closer neighbor!
                                                          |
                                             Greedy routing resumes
```

---

## 4. Geocasting: From Unicast Forwarding to In-Zone Flooding

Geographic routing distinguishes two major phases:
1. **Greedy Transit Phase (Ingress to Perimeter):** As long as the packet is outside the destination circle ($Distance > R$), it is routed in pure hop-by-hop unicast towards the geographic center.
2. **In-Zone Broadcast Phase (In-Zone Geocast Flooding):** As soon as the bundle crosses radius $R$ of the target perimeter, it switches to local flooding: **all nodes located inside the geographic zone exchange and deliver the message locally**, ensuring that all rescue teams present in the zone receive the order or alert.

---

## 5. Wire CDDL Specification: The `spatial_scope` Facet

In [Article 0](./article-0-intro.en.md), we specified a generic modular extension block (**Type 200** in the IANA experimental range of [RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html)).

**Facet 5 (`spatial_scope`)** of **[mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl#L41-L47)** precisely formalizes this payload:

```cddl
mesh-routing-data = {
    ? 1 => legacy-bridge-id: (bytes / uint),
    ? 2 => replication-control: replication-control,
    ? 3 => trajectory-control: trajectory-control,
    ? 4 => opportunistic-threshold: float,
    ? 5 => spatial-scope: spatial-scope
}

spatial-scope = {
    1 => center-lat-deg: float,       ; Latitude in decimal degrees (-90.0 to +90.0)
    2 => center-lon-deg: float,       ; Longitude in decimal degrees (-180.0 to +180.0)
    ? 3 => center-alt-meters: float,  ; Altitude in meters
    ? 4 => radius-meters: float,      ; Radius in meters (0 = exact point)
    ? 5 => radius-deg: float          ; Radius in degrees for fast calculations
}
```

- If `radius == 0`: Point-to-point geographic routing toward an exact position.
- If `radius > 0`: Geocast toward a circular zone (rescue perimeter or emergency area).
- Deduplication is guaranteed by the **canonical Bundle ID** `(source, time, sequence)` and propagation restriction by the **Hop Count Block (Type 10)**.

---

## 6. Declarative Modeling under Open Policy Agent (OPA)

The directory **[policies/geodtn/](./policies/geodtn/)** formalizes spatial arbitration rules.

### 6.1. Ingress: Local Geographic Delivery ([ingress.rego](./policies/geodtn/ingress.rego))

At ingress, a bundle is delivered locally if the EID matches, **OR if the bundle is a Geocast and the local node is physically located inside the spatial perimeter**:

```rego
# Ingress Rule 2: Local delivery if EID or geographic position matches
decision := {
    "action": "DELIVER_LOCAL",
    "reason": "Local delivery: node matches EID or is inside targeted Geocast spatial scope",
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    helpers.is_local_destination(input.bundle, input.node)
}
```

The function [helpers.is_local_destination](./policies/geodtn/helpers.rego#L37-L50) calculates the Euclidean distance:
$$\text{dist}^2 = (\text{lat}_\text{node} - \text{lat}_\text{center})^2 + (\text{lon}_\text{node} - \text{lon}_\text{center})^2 \le R^2$$

### 6.2. Contact: Greedy Forwarding vs Void Traversal ([contact.rego](./policies/geodtn/contact.rego))

When a contact is established with a neighbor:

1. **In-Zone Geocast Flooding:** If both nodes are already inside the target zone, the bundle is re-broadcast (`FORWARD_GEOCAST_IN_ZONE`).
2. **Greedy Routing:** If the peer is closer to the target coordinates than the local node, immediate transmission (`FORWARD_GREEDY`).
3. **Void Traversal (Carry-and-Forward):** If no neighbor is closer, OPA mandates storage retention (`SKIP`), avoiding sterile loops.

```rego
# Contact Rule 5: Greedy Forwarding
decision := {
    "action": "FORWARD_GREEDY",
    "reason": "Greedy geographic forwarding: peer is closer to target spatial coordinates",
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    input.contact.peer_eid != input.bundle.primary.destination
    not is_in_zone_geocast_active(input)
    
    scope := helpers.get_spatial_scope(input.bundle)
    scope != null
    
    my_coords := object.get(input.node, "coordinates", null)
    peer_coords := object.get(input.contact, "coordinates", null)
    my_coords != null
    peer_coords != null
    
    helpers.is_peer_closer(peer_coords, my_coords, scope.center_lat_deg, scope.center_lon_deg)
}

# Contact Rule 6: Local Void -> DTN Retention
decision := {
    "action": "SKIP",
    "reason": "Local minimum void: peer is not closer to target coordinates, holding bundle (Greedy-Carry-and-Forward)",
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    input.contact.peer_eid != input.bundle.primary.destination
    not is_in_zone_geocast_active(input)
    
    scope := helpers.get_spatial_scope(input.bundle)
    scope != null
    
    my_coords := object.get(input.node, "coordinates", null)
    peer_coords := object.get(input.contact, "coordinates", null)
    
    is_not_closer(peer_coords, my_coords, scope)
}
```

---

## 7. Validation by OPA Unit Tests (140/140 PASS)

A suite of 16 specific unit tests ([policies/geodtn/geodtn_test.rego](./policies/geodtn/geodtn_test.rego)) covers all geographic behaviors:
- Local delivery of a Geocast based solely on the node's GPS location.
- Greedy progression towards a peer moving closer to the target.
- Void detection (*local void*) and switch to temporary storage (*Greedy-Carry-and-Forward*).
- In-zone broadcast upon reaching the geographic perimeter.
- Compliance with *Split Horizon* (Type 6) and *Hop Count* (Type 10).

Running the repository's full test suite:

```bash
opa test ./policies -v
```

```text
policies/aprs/aprs_test.rego:           13 tests passed
policies/babel/babel_test.rego:         16 tests passed
policies/cgr/cgr_test.rego:             16 tests passed
policies/contact_test.rego:              5 tests passed
policies/flood/flood_test.rego:         17 tests passed
policies/geodtn/geodtn_test.rego:       16 tests passed
policies/ingress_test.rego:              6 tests passed
policies/maxprop/maxprop_test.rego:     16 tests passed
policies/prophet/prophet_test.rego:     16 tests passed
policies/reticulum/reticulum_test.rego: 16 tests passed
policies/storage_test.rego:              3 tests passed
--------------------------------------------------------------------------------
PASS: 140/140
```

---

## 8. The Grand Periodic Table of DTN Routing

With this eighth and final foundational article, our series concludes the exhaustive exploration of major routing paradigms:

| Algorithm | Paradigm | Addressing Format | Arbitration Metric | Failure & Void Handling |
| :--- | :--- | :--- | :--- | :--- |
| **APRS ([Art. 1](./article-1-aprs.en.md))** | Source routing & alias | Callsigns (`NOCALL`) | Alias consumption (`WIDE-n-N`) | Packet loss |
| **Meshtastic ([Art. 2](./article-2-flood.en.md))** | Managed flooding | 32-bit NodeNum | Physical SNR backoff | Redundant flooding |
| **Spray & Wait ([Art. 2](./article-2-flood.en.md))** | Strict quotas | Canonical URI EID | Binary quota split $L/2$ | Direct waiting (Wait Phase) |
| **PRoPHET ([Art. 3](./article-3-prophet.en.md))** | Encounter history probabilistic | Canonical URI EID | Encounter predictability $P_{(A, B)}$ | Eviction by low utility |
| **MaxProp ([Art. 4](./article-4-maxprop.en.md))** | Dijkstra & Buffer Sorting | Canonical URI EID | Log cost $-\log(P) + 0.01 \times \text{Hops}$ | Purge by Cleared List |
| **Reticulum ([Art. 5](./article-5-reticulum.en.md))** | Reactive distance vector | 16-byte cryptographic hash | Strict hops via signed Announces | DTN buffer hold |
| **Babel / AREDN ([Art. 6](./article-6-babel-aredn.en.md))** | Proactive & Hybrid MANET | EID / Subnet | Feasible Distance (FD) & ETX | **HYMAD** ferry gateway |
| **CGR ([Art. 7](./article-7-cgr.en.md))** | Spatial deterministic | Interplanetary EID | *Earliest Delivery Time* (EDT) | Deterministic preventive drop |
| **GeoDTN ([Art. 8](./article-8-geodtn.en.md))** | Geographic & Geocasting | Spatial coordinates (lat, lon) | Euclidean distance to target | **Greedy-Carry-and-Forward** |

---

## 9. Series Conclusion

The combination of **Bundle Protocol version 7 ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html))** and a declarative policy engine like **Open Policy Agent (OPA)** fulfills a long-standing promise of network engineering:

1. **Emancipation from IP addresses:** Whether the address is an amateur radio callsign, an Ed25519 public key hash, a Martian orbital point, or GPS coordinates, the BPv7 Primary Block carries it with the same canonical rigor.
2. **Total decoupling of logic:** The transport engine (managing LoRa/VHF/Wi-Fi radio interfaces, CBOR serialization, and disk storage) no longer needs to be rewritten for every new algorithm. A simple Rego policy modification transforms a CGR space router into a GeoDTN emergency beacon or a Reticulum self-sovereign node.
3. **Invulnerability to disruptions:** Whether dealing with interplanetary light-minutes or terrestrial mountainous terrain, the fundamental principle of *Store-Carry-and-Forward* ensures that no data is sacrificed.

---

👉 **Next Article (Synthesis & Outlook):** [Article 9 — Architectural Synthesis: Policy-Driven DTN Routing with OPA, Modular Extension Block, and Control Plane Unification](./article-9-synthese-architecture.en.md)
