# Article 6 — Proactive Mesh Networks and MANET-DTN Hybrids: AREDN, Babel (RFC 8966), and the HYMAD Architecture under Open Policy Agent

> **Series:** *Transposing Mesh & Opportunistic Routing Algorithms to DTN (BPv7)*  
> **Previous Articles:**  
> - [Article 0 — The Foundations of DTN Routing with Open Policy Agent](./article-0-intro.en.md)  
> - [Article 1 — Transposing APRS Digipeating (AX.25 WIDE n-N) to DTN (BPv7)](./article-1-aprs.en.md)  
> - [Article 2 — Taming Flooding in DTN: From Epidemic to Spray and Wait and Meshtastic Managed Flooding](./article-2-flood.en.md)  
> - [Article 3 — Opportunistic Routing and Encounter History: PRoPHET (RFC 6693) under Open Policy Agent](./article-3-prophet.en.md)  
> - [Article 4 — Probabilistic Routing and Resource-Constrained Buffer Management: MaxProp and its Theoretical Optimizations (HP-MaxProp)](./article-4-maxprop.en.md)  
> - [Article 5 — Hybrid Routing, Distance-Vector, and Cryptographic Addressing: Reticulum (RNS) Transposed to DTN](./article-5-reticulum.en.md)  
> **CDDL Specifications:** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl), [prophet.cddl](./prophet.cddl), [reticulum.cddl](./reticulum.cddl) & [babel.cddl](./babel.cddl)  
> **Policy Code:** [policies/babel/](./policies/babel/) ([ingress.rego](./policies/babel/ingress.rego), [contact.rego](./policies/babel/contact.rego), [storage.rego](./policies/babel/storage.rego), [helpers.rego](./policies/babel/helpers.rego), [constants.rego](./policies/babel/constants.rego), [babel_test.rego](./policies/babel/babel_test.rego))

---

## 1. The High-Throughput Island Paradox: The AREDN Case

Throughout the first five installments of this series, we focused on radio links with severe bandwidth constraints (LoRa, AX.25 VHF/UHF, HF) or purely opportunistic setups (unplanned physical encounters, PRoPHET predictabilities, and MaxProp scheduling).

In emergency response and crisis management operations, another mesh ecosystem plays a vital role: **AREDN (*Amateur Radio Emergency Data Network*)**.
AREDN repurposes commercial off-the-shelf Wi-Fi routers and directional antennas (Ubiquiti, MikroTik, TP-Link, GL.iNet) to transmit on amateur radio bands (2.4 GHz, 3.4 GHz, 5.8 GHz) at higher power levels and on reserved channels. The result is spectacular: **operational mesh networks running at several tens of megabits per second**, capable of carrying VoIP, real-time IP CCTV surveillance feeds, and tactical map servers.

However, in actual operational theaters (earthquakes, floods, major storms), a geographical and logistical pitfall inevitably emerges: **archipelago partitioning**.
- One AREDN cluster perfectly covers a valley or a stricken urban center.
- Another AREDN cluster is deployed around a field hospital 50 km away.
- Between the two: mountainous terrain blocking direct line of sight (LOS), a destroyed microwave backbone link, or a repeater failure on an inaccessible peak.

Traditional mesh protocols (OLSR, Babel, B.A.T.M.A.N.) are engineered to route IP packets with a latency of a few milliseconds. When faced with a complete partition, **they declare remote destinations unreachable and immediately discard packets**.

This is where the **HYMAD (*Hybrid DTN-MANET routing*)** paradigm comes into play:
> **Within a connected island:** Use a high-performance proactive mesh protocol (Babel / AREDN) to guarantee instantaneous next-hop forwarding.  
> **Between disjoint islands:** Seamlessly switch to Bundle Protocol v7 (BPv7) and *Store-Carry-and-Forward* via mobile data carriers (*data ferries*: emergency vehicles, drones, helicopters, or intermittent satellite/HF links).

---

## 2. The Babel Protocol (RFC 8966): Loop-Free Distance-Vector

Originally based on OLSRv1 ([RFC 3626](https://www.rfc-editor.org/rfc/rfc3626.html)), the AREDN firmware made a strategic transition to **Babel ([RFC 8966](https://www.rfc-editor.org/rfc/rfc8966.html))**.

Why prefer Babel over a link-state protocol like OSPF or OLSR?
1. **Frugality:** Babel does not attempt to synchronize the complete graph topology on every node.
2. **Real radio link metrics (ETX / RTT):** Babel continuously measures bidirectional radio link quality via a symmetric `Hello` / `IHU` (*I Heard You*) exchange.
3. **Mathematical Loop Freedom:** Achieved through the joint use of **Feasible Distance (FD)** and **sequence numbers (Seqno)**.

```
                   Babel Loop-Free Mechanism (RFC 8966)
                   ====================================

       +-------------------------------------------------------------+
       |                 Feasible Distance: FD(D)                    |
       |  (Smallest historical metric ever observed towards D)       |
       +-------------------------------------------------------------+
                                      |
                      An update arrives with metric M
                                      |
                          +------------+------------+
                          |                         |
                     M < FD(D)                 M >= FD(D)
                          |                         |
                          v                         v
               [ CONDITION SATISFIED ]   [ UNFEASIBLE (Risk of loop) ]
                          |                         |
                  Route accepted!            Route rejected!
                  FD(D) = min(FD, M)                |
                                             Triggering a
                                             "Seqno Request" towards D
                                                    |
                                             D replies with (seqno + 1)
                                                    |
                                             New sequence accepted!
```

### 2.1. The Feasibility Condition
In standard distance-vector routing (Bellman-Ford), if a link breaks, neighboring routers can advertise increasingly costly routes to each other for the destination, creating the "count-to-infinity" problem.

Babel solves this problem elegantly:
- Each router maintains for every destination $D$ its **Feasible Distance** $FD(D)$, which is the lowest metric recorded since the last sequence reset.
- An advertisement from a neighbor with metric $M$ is adopted only if **$M < FD(D)$**. This condition rigorously guarantees that no cycle can form.

### 2.2. Sequence Numbers (*Seqno*) and Reactive Repair
If all routes to $D$ degrade (for example, the best antenna broke down), the actual metric becomes higher than $FD(D)$. The feasibility condition then blocks any update.
Rather than waiting or risking a loop:
1. The node emits a **`Seqno Request`** control message targeted at $D$.
2. The target router $D$ increments its sequence number: $s \leftarrow s + 1$.
3. $D$ broadcasts an `Update` announcement with this new sequence number.
4. Upon receiving this higher $seqno$, all intermediate nodes safely reset their Feasible Distance $FD(D) = M_{new}$.

---

## 3. Architectural Decoupling and `babel.cddl` Specification

### 3.1. Zero Wire Overhead for DTN Data
As with Meshtastic ([Article 2](./article-2-flood.en.md)) and Reticulum ([Article 5](./article-5-reticulum.en.md)):
- Data bundles traversing the AREDN/DTN infrastructure **strictly use standard BPv7 blocks ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html))**.
- The destination is carried by the standard EID (e.g., `dtn://aredn/camera-relay-04/` or `ipn:42.1`).
- Physical loop breaking as a last resort is delegated to the **Hop Count Block (Type 10)**.
- Deduplication relies on the **canonical Bundle ID** `(source, time, sequence)`.

### 3.2. CDDL Specification of Control Messages ([babel.cddl](./babel.cddl))
Signaling exchanges between Babel/AREDN routers are encapsulated inside the payload of CBOR administrative bundles:

```cddl
; Babel control message carried in the payload of an administrative bundle
babel-control-bundle = {
    1 => message-type: babel-message-type,
    2 => sender-router-id: bytes .size 8,   ; Unique router ID (64 bits)
    3 => timestamp-ms: uint,                ; DTN creation clock
    4 => payload: babel-payload             ; Payload according to type
}

babel-message-type = &(
    msg-hello: 1,         ; Neighbor discovery and heartbeat
    msg-ihu: 2,           ; "I Heard You": bidirectional validation (ETX)
    msg-update: 3,        ; Proactive route update (prefix, seqno, metric)
    msg-route-request: 4, ; Route update request
    msg-seqno-request: 5  ; Sequence reset request
)

; Route announcement (Update)
update-payload = {
    1 => prefix-eid: tstr,                  ; Destination (EID or prefix)
    2 => router-id: bytes .size 8,          ; Originating Router-ID
    3 => seqno: uint .size 2,               ; Sequence number
    4 => metric: uint,                      ; Accumulated metric (0 to 65535)
    5 => interval-ms: uint                  ; Validity duration
}

; Urgent sequence increment request (Seqno Request)
seqno-request-payload = {
    1 => prefix-eid: tstr,
    2 => router-id: bytes .size 8,
    3 => seqno: uint .size 2,
    4 => hop-count: uint
}
```

---

## 4. HYMAD Hybridization under Open Policy Agent (OPA)

The directory **[policies/babel/](./policies/babel/)** implements the full logic as declarative Rego rules.

### 4.1. Ingress: Loop-Free Bellman-Ford Arbitration ([ingress.rego](./policies/babel/ingress.rego))

Upon receiving a Babel `Update` signaling bundle, OPA evaluates whether the route should update the local router's table:

```rego
# Ingress Rule 6: Ingestion of a Babel UPDATE message
decision := {
    "action": "ACCEPT_BABEL_UPDATE",
    "reason": sprintf("Babel update accepted: route to %v via %v updated (metric: %v, seqno: %v)", [
        prefix, peer_eid, total_metric, update_seqno
    ]),
    "mutations": [
        {
            "operation": "UPDATE_ROUTING_TABLE",
            "prefix_eid": prefix,
            "next_hop": peer_eid,
            "metric": total_metric,
            "seqno": update_seqno,
            "feasible_distance": total_metric,
            "expires_at_ms": input.current_dtn_time_ms + constants.default_route_expiry_ms
        },
        {
            "block_type": base_constants.block_type_hop_count,
            "operation": "SET_FIELD",
            "field": "hop_count",
            "value": hcb.hop_count + 1
        }
    ]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    helpers.is_babel_control(input.bundle)
    hcb := base_helpers.get_hop_count_block(input.bundle)
    
    update := object.get(input.ingress, "babel_update", object.get(input.bundle, "babel_update", {}))
    prefix := update.prefix_eid
    adv_metric := update.metric
    update_seqno := update.seqno
    peer_eid := object.get(input.ingress, "peer_eid", input.bundle.primary.source)
    link_cost := object.get(input.ingress, "link_cost", 10)
    total_metric := min([adv_metric + link_cost, constants.metric_infinity])
    
    existing := helpers.get_route_entry(prefix, object.get(input.node, "routing_table", {}))
    helpers.should_update_babel_route(existing, update_seqno, total_metric, input.current_dtn_time_ms)
}
```

The helper function [helpers.should_update_babel_route](./policies/babel/helpers.rego#L51-L82) strictly applies the rules of the Feasibility Condition (RFC 8966 Section 3.5.1):
- If $seqno_{new} > seqno_{old}$: the originating router increased its sequence; the route is updated immediately and the metric is reset.
- If $seqno_{new} == seqno_{old}$ and $metric_{new} < metric_{old}$: the route is adopted because it offers a strictly better metric satisfying feasibility ($m < FD$).
- If $metric_{new} < FD(D)$: the metric is strictly below the historical Feasible Distance, guaranteeing complete freedom from loops.
- Otherwise: the update is ignored (`ACCEPT_BABEL_UPDATE_NO_CHANGE`), preventing any propagation of degraded or loop-creating metrics.

### 4.2. Contact: Proactive Forwarding or HYMAD Ferry Fallback ([contact.rego](./policies/babel/contact.rego))

When contact is established with a peer, the policy distinguishes between two regimes:

1. **Intra-Island Regime (High-Speed Mesh):**
   If the destination is present in the local Babel table with a valid metric, the bundle is routed via immediate unicast to the designated next-hop (`FORWARD_NEXT_HOP`).
2. **Inter-Island Regime (DTN Ferry / HYMAD):**
   If the destination is **unknown or unreachable within the local island**, and the contacted peer is identified as an inter-island mobile vector (`is_dtn_carrier == true`), OPA instructs immediate offloading to this ferry (`FORWARD_DTN_CARRIER`).
3. **Isolation Regime:**
   If no inter-island vector is present, the bundle is not dropped: it is retained in storage (`SKIP`), awaiting a future opportunity.

```rego
# Contact Rule 7: Offloading to inter-island DTN carrier (HYMAD)
decision := {
    "action": "FORWARD_DTN_CARRIER",
    "reason": "Destination unreachable via local AREDN mesh: offloading to opportunistic DTN inter-cluster carrier",
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_babel_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    not is_valid_route(route, input.current_dtn_time_ms)
    object.get(input.contact, "is_dtn_carrier", false) == true
}
```

### 4.3. Storage: Reactive Discovery via Route Requests ([storage.rego](./policies/babel/storage.rego))

During storage buffer audits, if a bundle resides in the buffer for a destination whose route has expired, OPA triggers a route request:

```rego
decision := {
    "action": "RETAIN_AND_REQUEST_ROUTE",
    "reason": "Destination route unknown or unfeasible: trigger Babel route request",
    "mutations": [{
        "operation": "TRIGGER_BABEL_ROUTE_REQUEST",
        "prefix_eid": input.bundle.primary.destination
    }]
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_babel_control(input.bundle)
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    not is_valid_route(route, input.current_dtn_time_ms)
    object.get(input.node, "enable_babel_requests", false) == true
}
```

---

## 5. Validation through OPA Unit Tests (108/108 PASS)

A suite of 16 specific unit tests ([policies/babel/babel_test.rego](./policies/babel/babel_test.rego)) validates the complete behavior:
- Route updates on new seqno vs. same seqno.
- Rejection of degraded metrics (feasibility condition).
- Strict unicast routing to the next-hop.
- HYMAD offloading to inter-island DTN carriers.
- Reactive triggering of route requests from storage.

Execution of the entire project test suite:

```bash
opa test ./policies -v
```

```text
policies/aprs/aprs_test.rego:
  13 tests passed (digipeating AX.25, Dire Wolf rules 6.1b, 6.3c, trapping §10)
policies/babel/babel_test.rego:
  data.dtn.babel_test.test_babel_ingress_local_delivery: PASS
  data.dtn.babel_test.test_babel_ingress_blacklisted_source: PASS
  data.dtn.babel_test.test_babel_ingress_expired: PASS
  data.dtn.babel_test.test_babel_ingress_hop_limit_reached: PASS
  data.dtn.babel_test.test_babel_ingress_update_new_route: PASS
  data.dtn.babel_test.test_babel_ingress_update_newer_seqno: PASS
  data.dtn.babel_test.test_babel_ingress_update_lower_metric_same_seqno: PASS
  data.dtn.babel_test.test_babel_ingress_update_worse_metric_ignored: PASS
  data.dtn.babel_test.test_babel_ingress_data_forward: PASS
  data.dtn.babel_test.test_babel_contact_direct_destination: PASS
  data.dtn.babel_test.test_babel_contact_control_broadcast: PASS
  data.dtn.babel_test.test_babel_contact_forward_matching_next_hop: PASS
  data.dtn.babel_test.test_babel_contact_skip_non_next_hop_peer: PASS
  data.dtn.babel_test.test_babel_contact_hymad_dtn_carrier_bridging: PASS
  data.dtn.babel_test.test_babel_contact_skip_isolated_unknown_route: PASS
  data.dtn.babel_test.test_babel_storage_trigger_route_request: PASS
policies/contact_test.rego:
  5 tests passed (contact CLA foundations, split-horizon, lifetime)
policies/flood/flood_test.rego:
  17 tests passed (binary/source Spray & Wait, Meshtastic SNR backoff and contention)
policies/ingress_test.rego:
  6 tests passed (ingress foundations, validation, hop decrement, deduplication)
policies/maxprop/maxprop_test.rego:
  16 tests passed (logarithmic cost, smooth hop penalty, 2-hop gossip, cleared list)
policies/prophet/prophet_test.rego:
  16 tests passed (mathematical equations, RIB handshake, selective eviction)
policies/reticulum/reticulum_test.rego:
  16 tests passed (cryptographic distance-vector, signed announcements, Store-Carry-and-Forward)
policies/storage_test.rego:
  3 tests passed (Bundle Age Block Type 7 handling)
--------------------------------------------------------------------------------
PASS: 108/108
```

---

## 6. Global Comparative Overview of the 6 Protocols

This sixth article completes our comparative matrix of major routing families transposed onto DTN:

| Criterion | APRS AX.25 ([Art. 1](./article-1-aprs.en.md)) | Meshtastic ([Art. 2](./article-2-flood.en.md)) | PRoPHET RFC 6693 ([Art. 3](./article-3-prophet.en.md)) | MaxProp / HP-MaxProp ([Art. 4](./article-4-maxprop.en.md)) | Reticulum RNS ([Art. 5](./article-5-reticulum.en.md)) | AREDN / Babel / HYMAD ([Art. 6](./article-6-babel-aredn.en.md)) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Fundamental Paradigm** | Source routing & aliases | Managed flooding | Probabilistic opportunistic | Dijkstra + Buffer Scheduling | Reactive distance-vector | **MANET-DTN Hybrid (Proactive + Ferry)** |
| **Target Medium & Speed** | AX.25 frame 1200 baud | LoRa 0.3 - 5 kbps | Bluetooth / Urban Wi-Fi | Vehicular & LoRa (2-hop) | Multi-medium (HF/LoRa/UDP) | **High-Speed Wi-Fi (10-100 Mbps) + Ferries** |
| **Loop Freedom Guarantee** | Alias decrement & Type 6 | Hop Count Type 10 & IDs | Hop Count Type 10 | Hop Count Type 10 | Strict Hop Count & increasing metric | **Feasibility Distance (FD) & Seqnos** |
| **DTN Data Wire Blocks** | Type 200 (`trajectory_control`) | **Zero custom block** (Pure BPv7) | Optional Type 200 (`threshold`) | **Zero custom block** (Pure BPv7) | **Zero custom block** (Pure BPv7) | **Zero custom block** (Pure BPv7) |
| **Inter-Node Signaling** | None (blind broadcast) | None (pre-shared channels) | RIB & SV Handshake ([prophet.cddl](./prophet.cddl)) | Prob-Vector & Cleared List ([maxprop.cddl](./maxprop.cddl)) | Signed Announces ([reticulum.cddl](./reticulum.cddl)) | Hellos, IHU, Updates ([babel.cddl](./babel.cddl)) |
| **Isolation Behavior** | Packet lost if uncaught | Suppressed if out of reach | Stored in memory until contact | Sorted and purged via Cleared List | Retained in buffer until announce | **Automatic offloading to DTN ferry** |

---

## 7. Series Assessment and Next Frontiers

Exploring APRS, Spray and Wait, Meshtastic, PRoPHET, Reticulum, and now AREDN/Babel/HYMAD leads to a clear overarching takeaway:
1. **Bundle Protocol v7 (RFC 9171) is a universal metamodel.** It unifies physical transport under a canonical format without imposing rigid assumptions on the underlying topology.
2. **Open Policy Agent (OPA) turns the router into an expert system.** By separating decision logic from low-level convergence layer code, we can swap or hybridize radically different routing algorithms (MANET vs. DTN) with a single line of declarative policy.
3. **The future of emergency mesh networking is hybrid.** Tomorrow's architectures will no longer choose between real-time mesh and delay tolerance: they will combine both, as demonstrated with AREDN-DTN hybridization.

In the next article ([Article 7](./article-7-cgr.en.md)), we will cross terrestrial boundaries to explore the spatial DTN standard: **Contact Graph Routing (CGR / SABR - CCSDS 734.3-B-1)** based on deterministic orbital contact schedules.

---

👉 **Next Article:** [Article 7 — Deterministic Contact Graph Routing: Contact Graph Routing (CGR / SABR - CCSDS 734.3-B-1) under Open Policy Agent](./article-7-cgr.en.md)
