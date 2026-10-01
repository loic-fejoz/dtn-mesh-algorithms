# Article 7 — Deterministic Space Routing: Contact Graph Routing (CGR / SABR - CCSDS 734.3-B-1) under Open Policy Agent

> **Series:** *Transposing Mesh & Opportunistic Routing Algorithms to DTN (BPv7)*  
> **Previous Articles:**  
> - [Article 0 — The Foundations of DTN Routing with Open Policy Agent](./article-0-intro.en.md)  
> - [Article 1 — Transposing APRS Digipeating (AX.25 WIDE n-N) to DTN (BPv7)](./article-1-aprs.en.md)  
> - [Article 2 — Taming Flooding in DTN: From Epidemic to Spray and Wait and Meshtastic Managed Flooding](./article-2-flood.en.md)  
> - [Article 3 — Opportunistic Routing and Encounter History: PRoPHET (RFC 6693) under Open Policy Agent](./article-3-prophet.en.md)  
> - [Article 4 — Probabilistic Routing and Resource-Constrained Buffer Management: MaxProp and its Theoretical Optimizations (HP-MaxProp)](./article-4-maxprop.en.md)  
> - [Article 5 — Hybrid Routing, Distance-Vector, and Cryptographic Addressing: Reticulum (RNS) Transposed to DTN](./article-5-reticulum.en.md)  
> - [Article 6 — Proactive Mesh Networks and MANET-DTN Hybrids: AREDN, Babel (RFC 8966), and the HYMAD Architecture under Open Policy Agent](./article-6-babel-aredn.en.md)  
> **CDDL Specifications:** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl), [prophet.cddl](./prophet.cddl), [maxprop.cddl](./maxprop.cddl), [reticulum.cddl](./reticulum.cddl), [babel.cddl](./babel.cddl) & [cgr.cddl](./cgr.cddl)  
> **Policy Code:** [policies/cgr/](./policies/cgr/) ([ingress.rego](./policies/cgr/ingress.rego), [contact.rego](./policies/cgr/contact.rego), [storage.rego](./policies/cgr/storage.rego), [helpers.rego](./policies/cgr/helpers.rego), [constants.rego](./policies/cgr/constants.rego), [cgr_test.rego](./policies/cgr/cgr_test.rego))

> ℹ️ **Editorial Transparency Note (EU AI Act Alignment):** This article was generated with AI assistance under the editorial direction and structuring of a human author, who assumes responsibility for its technical review, verification, and content (ongoing proofreading).

---

## 1. From Terrestrial Randomness to Celestial Determinism

Until now, all routing algorithms studied in this series shared a fundamental assumption: **unpredictability or statistical estimation of contacts**.
- In APRS and Meshtastic, transmissions occur dynamically on shared channels.
- In Spray & Wait, PRoPHET, and MaxProp, nodes discover their neighbors during opportunistic encounters driven by human or vehicular movement.
- In Reticulum and Babel, routes emerge dynamically via announcements or probes over fluctuating radio links.

However, the historical cradle of **Delay-Tolerant Networking** is not terrestrial: it is space exploration and the **Interplanetary Internet (IPN)** envisioned by Vint Cerf, Adrian Hooke, and Scott Burleigh at NASA's Jet Propulsion Laboratory (JPL).

In interplanetary space (Martian missions, Jupiter probes, Low Earth Orbit (LEO) satellite constellations, Artemis lunar orbiters):
1. **Distances are titanic:** One-Way Light Time (OWLT) propagation delay between Earth and Mars ranges from **3 to 22 minutes**.
2. **Link disruptions are periodic and predictable:** A lander at the bottom of a Martian crater can only communicate with an orbiter when the latter passes over its zenith (a visibility window of 10 to 15 minutes, twice per Martian sol). A Deep Space Network (DSN) ground station at Goldstone, Madrid, or Canberra is pointed at a probe only according to an antenna slot reserved weeks in advance.
3. **Kepler's laws dictate topology:** Celestial bodies and spacecraft trajectories are known to the millisecond.

In this context, waiting for an "opportunistic encounter" or blindly flooding space vacuum would be absurd. The premier algorithm for space DTN is **Contact Graph Routing (CGR)**, formalized by Scott Burleigh (NASA/JPL, `draft-burleigh-dtnrg-cgr`) and standardized by the CCSDS under the **SABR (Schedule-Aware Bundle Routing, CCSDS 734.3-B-1)** standard.

---

## 2. The Theoretical Pillars of CGR and the CCSDS SABR Standard

CGR does not build a routing table over a static spatial graph, but over a **Spatio-Temporal Graph (*Time-Expanded Graph*)**.

```
             Spatio-Temporal Representation of a Contact Plan
             ===============================================

   Earth Node    [ Window 1 : 00:00 -> 00:30 ]
                        \  (Data rate: 2 Mbps, OWLT: 8 min)
                         v
   Mars Orbiter          [ Window 2 : 01:15 -> 01:30 ]
                                \  (Data rate: 500 kbps, OWLT: 0.05 s)
                                 v
   Mars Surface Rover            [ Final Reception: EDT = 01:25 ]
```

### 2.1. The Contact Plan (Schedule of Contacts)
The core of CGR is the **Contact Plan**, a deterministic registry shared by all nodes in a mission:
- **Scheduled Contacts:** A tuple $(\text{Source}, \text{Dest}, t_\text{start}, t_\text{end}, \text{Rate}, \text{Capacity})$ specifying with certainty that a point-to-point link will be active between times $t_\text{start}$ and $t_\text{end}$ at a precise data rate.
- **Range Records:** Specify physical propagation delays $OWLT(t)$ (the time electromagnetic signals take to traverse the distance at light speed).

### 2.2. Spatio-Temporal Dijkstra Tree and EDT
When a bundle for `dtn://mars-rover/` is submitted to the terrestrial CGR router:
1. CGR projects future contacts forward in time.
2. It applies Dijkstra's algorithm where edge cost is not physical distance, but the **Earliest Delivery Time (EDT)**.
3. For each hop, the bundle can only depart at $t \ge \max(\text{Arrival}, t_\text{start})$ and will arrive at the next node at $t_\text{arrival} = t_\text{departure} + OWLT + \frac{\text{Size}}{\text{Rate}}$.

### 2.3. Volume Management and Deterministic Preventive Rejection
Every contact window has a finite byte capacity:
$$\text{Capacity} = (t_\text{end} - t_\text{start}) \times \text{Rate}$$
As each bundle is scheduled onto a contact, the remaining capacity is decremented.
If a window's capacity is exhausted, CGR directs surplus bundles to the next window or an alternate relay.

**CGR's massive advantage over terrestrial protocols:**
If CGR evaluation proves that the best contact sequence results in an $EDT > \text{Bundle Lifetime}$, **the bundle is destroyed immediately at the source or first relay!** It is mathematically impossible for it to reach its destination before expiring: dropping it preventively avoids wasting precious megabytes of onboard storage and radio bandwidth.

---

## 3. CDDL Wire Specification: `cgr.cddl`

Data bundles travel in standard BPv7 format ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html)).
The dissemination and revocation of contact schedules between control centers and space probes are specified in CBOR in **[cgr.cddl](./cgr.cddl)**:

```cddl
; CGR control message carried in the payload of an administrative bundle
cgr-control-bundle = {
    1 => message-type: cgr-message-type,
    2 => issuer-eid: tstr,                  ; Issuing authority EID
    3 => timestamp-ms: uint,                ; DTN emission clock
    4 => payload: cgr-payload               ; Payload
}

cgr-message-type = &(
    msg-contact-plan-update: 1, ; Scheduled contact window update
    msg-contact-plan-revoke: 2, ; Contact cancellation (transmitter failure)
    msg-range-update: 3         ; OWLT distance update
)

scheduled-contact = {
    1 => contact-id: uint,                  ; Unique contact ID
    2 => from-eid: tstr,                    ; Sender node
    3 => to-eid: tstr,                      ; Receiver node
    4 => start-time-ms: uint,               ; Window start time
    5 => end-time-ms: uint,                 ; Window end time
    6 => data-rate-bps: uint,               ; Transmission data rate
    ? 7 => max-capacity-bytes: uint,        ; Total capacity
    ? 8 => confidence: float                ; Confidence index
}
```

---

## 4. Declarative Modeling under Open Policy Agent (OPA)

The directory **[policies/cgr/](./policies/cgr/)** implements spatio-temporal routing decisions.

### 4.1. Contact: Synchronized Transmission over Active Windows ([contact.rego](./policies/cgr/contact.rego))

Unlike terrestrial protocols where a peer's physical presence permits immediate transmission, CGR requires three concurrent conditions:
1. The peer matches the next-hop designated by the optimal CGR sequence (`input.contact.peer_eid == path.next_hop_eid`).
2. The current DTN clock falls strictly within the active contact window ($t_\text{start} \le \text{Now} \le t_\text{end}$).
3. The window's residual capacity is greater than or equal to the bundle size.

```rego
# Contact Rule 5: Deterministic transmission during an active contact window
decision := {
    "action": "FORWARD_CGR_SCHEDULED",
    "reason": sprintf("CGR contact window active with %v (EDT: %v, remaining capacity: %v)", [
        path.next_hop_eid,
        path.earliest_delivery_time_ms,
        path.remaining_capacity_bytes
    ]),
    "mutations": [{
        "operation": "DECREMENT_CONTACT_CAPACITY",
        "contact_id": path.first_contact_id,
        "bytes": bundle_size
    }]
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_cgr_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    
    path := helpers.get_cgr_path(input.bundle.primary.destination, object.get(input.node, "cgr_routes", {}))
    path != null
    input.contact.peer_eid == path.next_hop_eid
    helpers.is_path_viable(path, input.bundle, input.current_dtn_time_ms)
    
    contact := object.get(input.contact, "scheduled_contact", null)
    contact != null
    helpers.is_contact_active(contact, input.current_dtn_time_ms)
    
    bundle_size := object.get(input.bundle, "total_size_bytes", 1024)
}
```

If the peer is in sight but the window has not opened yet (e.g., antenna pointing unlocked) or capacity is exhausted, OPA returns `action: "SKIP"`, holding the bundle in storage.

### 4.2. Storage: Preventive Elimination of Infeasible Bundles ([storage.rego](./policies/cgr/storage.rego))

During periodic storage buffer maintenance:

```rego
# Storage Rule 3: Deterministic preventive drop
decision := {
    "action": "DROP_INFEASIBLE_SCHEDULE",
    "reason": "Deterministic CGR check: Earliest Delivery Time exceeds bundle lifetime",
    "generate_status_report": base_helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_cgr_control(input.bundle)
    path := helpers.get_cgr_path(input.bundle.primary.destination, object.get(input.node, "cgr_routes", {}))
    is_path_impossible(path, input.bundle)
}

is_path_impossible(path, bundle) if {
    path != null
    creation_time := bundle.primary.creation_timestamp.time
    lifetime := bundle.primary.lifetime
    path.earliest_delivery_time_ms > (creation_time + lifetime)
}
```

This rule highlights the power of OPA's declarative model: a doomed packet is discarded days or weeks before its theoretical expiration, safeguarding satellite memory buffers against saturation.

---

## 5. Validation through OPA Unit Tests (124/124 PASS)

A suite of 16 specific unit tests ([policies/cgr/cgr_test.rego](./policies/cgr/cgr_test.rego)) covers all CGR use cases:
- Validation of active vs. future vs. expired temporal windows.
- Residual capacity decrement upon scheduling transmission.
- Refusal to transmit if bundle size exceeds window remaining capacity.
- Deterministic preventive drop when EDT exceeds lifetime ($EDT > \text{Lifetime}$).

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
policies/ingress_test.rego:              6 tests passed
policies/maxprop/maxprop_test.rego:     16 tests passed
policies/prophet/prophet_test.rego:     16 tests passed
policies/reticulum/reticulum_test.rego: 16 tests passed
policies/storage_test.rego:              3 tests passed
--------------------------------------------------------------------------------
PASS: 124/124
```

---

## 6. Comparative Synthesis: Opportunistic vs. Deterministic

| Criterion | Opportunistic Approaches (PRoPHET / MaxProp) | Space Deterministic Approach (CGR / CCSDS SABR) |
| :--- | :--- | :--- |
| **Target Environment** | Urban networks, vehicles, ad-hoc sensors | Deep space (Earth, Moon, Mars), LEO constellations |
| **Contact Knowledge** | Real-time discovery, probabilistic | Predictive deterministic schedule (*Contact Plan*) |
| **Propagation Delay Handling** | Negligible (radio ms) | **Critical: OWLT Integration** (light-minutes) |
| **Routing Graph** | Instantaneous topology or local history | **Spatio-Temporal Graph** projected into the future |
| **Buffer Retention Policy** | Reactive eviction on saturation | **Deterministic preventive drop** if $EDT > \text{Lifetime}$ |
| **Capacity Management** | Unknown prior to contact | Volume tracked and decremented per window |

---

## 7. Outlook: Towards Geographic Routing and Geocasting

With CGR, we resolved scheduled routing when time and orbits govern the network.

But what happens on Earth when we have no pre-established schedule, no IP addresses, and no pre-mapped routers, but **only geographical position matters** (drone search for victims, emergency beacons, earthquake sensors)?

In the next article ([Article 8](./article-8-geodtn.en.md)), we will explore **Geographic Routing and Geocasting (GeoDTN / GPSR-DTN)** by leveraging the `spatial_scope` primitive from our CDDL specification!

---

👉 **Next Article:** [Article 8 — Geographic Routing and Geocasting in DTN: GeoDTN and Greedy-Carry-and-Forward under Open Policy Agent](./article-8-geodtn.en.md)
