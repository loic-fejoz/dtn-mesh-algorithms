# Article 3 — Opportunistic Routing and Encounter History: PRoPHET (RFC 6693) under Open Policy Agent

> **Series:** *Porting Mesh & Opportunistic Routing Algorithms to DTN (BPv7)*  
> **Previous articles:**  
> - [Article 0 — Foundations of DTN Routing with Open Policy Agent](./article-0-intro.en.md)  
> - [Article 1 — Porting APRS Digipeating (AX.25 WIDE n-N) to DTN (BPv7)](./article-1-aprs.en.md)  
> - [Article 2 — Taming Flooding in DTN: From Epidemic to Spray and Wait and Meshtastic Managed Flooding](./article-2-flood.en.md)  
> **CDDL Specifications:** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl) & [prophet.cddl](./prophet.cddl)  
> **Policy Code:** [policies/prophet/](./policies/prophet/) ([ingress.rego](./policies/prophet/ingress.rego), [contact.rego](./policies/prophet/contact.rego), [storage.rego](./policies/prophet/storage.rego), [helpers.rego](./policies/prophet/helpers.rego), [constants.rego](./policies/prophet/constants.rego), [prophet_test.rego](./policies/prophet/prophet_test.rego))

> ℹ️ **Editorial Transparency Note (EU AI Act Alignment):** This article was generated with AI assistance under the editorial direction and structuring of a human author, who assumes responsibility for its technical review, verification, and content (ongoing proofreading).

---

## 1. Beyond Blind Flooding: Non-Random Mobility

In the previous article ([Article 2](./article-2-flood.en.md)), we explored how **Spray and Wait** bounds replication a priori by setting a quota $L$, while **Meshtastic** suppresses radio storms via an SNR-weighted contention backoff. However, both approaches share an underlying assumption: **blind opportunism**. Any available relay node is treated indiscriminately as long as it is within reach.

In real-world scenarios (disaster-zone rescue networks, sensors carried by field teams, public transit, drone or animal fleets), human and asset movements are **not random**:
- Entities follow recurring trajectories (home-to-work commutes, patrols, logistical rounds).
- Certain nodes act as central hubs or natural bridges (*social hubs*, infrastructure gateways).
- If node $A$ frequently encounters node $B$, and node $B$ regularly encounters node $C$, then node $B$ constitutes an excellent vector for conveying a message from $A$ to $C$, even if $A$ and $C$ never cross paths directly.

It is on this realization that **PRoPHET (*Probabilistic Routing Protocol using History of Encounters and Transitivity*)** rests, initially proposed by Anders Lindgren et al. (2003) and standardized within the IRTF DTNRG in **[RFC 6693](https://www.rfc-editor.org/rfc/rfc6693.html)**.

---

## 2. Mathematical Foundations of RFC 6693

PRoPHET introduces for each node $A$ a scalar metric called **Delivery Predictability** denoted $P_{(A, B)} \in [0, 1]$ for any known destination $B$. The closer this value is to $1$, the higher the probability that node $A$ will succeed in delivering a bundle to $B$.

This metric evolves dynamically according to three discrete differential equations:

```
          +-------------------------------------------------------+
          | 1. Direct Encounter: P(a, b) increases               |
          |    P(a, b) = P(a, b)_old + (1 - P(a, b)_old) * P_enc  |
          +-------------------------------------------------------+
                                      |
                                      v
          +-------------------------------------------------------+
          | 2. Transitivity: P(a, c) benefits from ally b          |
          |    P(a, c) = P(a, c)_old + (1 - P(a, c)_old)          |
          |              * P(a, b) * P(b, c) * beta               |
          +-------------------------------------------------------+
                                      |
                                      v
          +-------------------------------------------------------+
          | 3. Temporal Aging: P decreases                        |
          |    P(a, b) = P(a, b)_old * (gamma ^ k)                |
          +-------------------------------------------------------+
```

### 2.1. Update During a Direct Encounter (*Direct Encounter*)
When node $A$ comes into physical contact with node $B$, its predictability toward $B$ is immediately re-evaluated upward:
$$P_{(A, B)} = P_{(A, B)\text{old}} + (1 - P_{(A, B)\text{old}}) \times P_\text{encounter}$$
- $P_\text{encounter} \in [0, 1]$ is a system parameter (default $0.75$ in RFC 6693).
- Thanks to the damping factor $(1 - P_{(A, B)\text{old}})$, the metric asymptotically approaches $1$ without ever exceeding it, rewarding encounter regularity.

### 2.2. Transitive Predictability (*Transitivity*)
If $A$ encounters $B$, they exchange their predictability tables (*Handshake / RIB exchange*). For every third-party destination $C$ known to $B$, node $A$ re-evaluates its own score:
$$P_{(A, C)} = P_{(A, C)\text{old}} + (1 - P_{(A, C)\text{old}}) \times P_{(A, B)} \times P_{(B, C)} \times \beta$$
- $\beta \in [0, 1]$ is the transitivity attenuation factor (default $0.25$).
- This property enables routing information to percolate through the network without requiring a centralized global map.

### 2.3. Temporal Aging (*Aging*)
If two nodes no longer cross paths, their mutual utility decreases over time:
$$P_{(A, B)} = P_{(A, B)\text{old}} \times \gamma^k$$
- $\gamma \in (0, 1)$ is the aging constant (default $0.98$).
- $k$ represents the number of time units elapsed since the last audit.

---

## 3. Architecture and Decoupling: Wire Format vs OPA Environment

As highlighted in our prior work, an elegant DTN implementation strictly separates wire data traversing the medium from data governing local policy decisions.

### 3.1. On the Wire: The Opportunistic Threshold (`opportunistic-threshold`)
Unlike heavy protocols that attempt to serialize the entire routing matrix inside every data bundle, **PRoPHET in DTN requires only an optional field in Type 200 extension block**:
```cddl
mesh-routing-data = {
    ? 1 => legacy-bridge-id: (bytes / uint), ; Optional external fingerprint
    ? 4 => opportunistic-threshold: float,   ; Minimal utility threshold required by sender
    ...
}
```
The sender of a sensitive bundle (e.g. a priority medical alert) can specify `opportunistic-threshold: 0.65`. Thus, a relay node will refrain from handing the bundle to a passerby whose predictability toward the destination is too low, avoiding unnecessary packet dispersion.

### 3.2. Inside the OPA Evaluation Environment (`input`)
Predictability tables $P_{(A, *)}$ and $P_{(B, *)}$ are local data structures maintained in RAM by the DTN daemon. They are injected into the OPA evaluation context in compliance with Part 2 of [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl):

- `input.node.delivery_predictabilities`: dictionary `{ "dtn://dest/": 0.45, ... }` computed by the local node.
- `input.contact.peer_predictabilities`: predictability vector transmitted by peer $B$ during Convergence Layer Adapter (CLA) establishment.
- `input.contact.held_bundle_ids`: peer's Summary Vector (list of canonical IDs it already holds).

### 3.3. Reconciliation with Hop Count Block (Type 10) and Bundle ID
- **Duplicate Detection:** The canonical Bundle ID `(source_eid, creation_timestamp.time, creation_timestamp.sequence_number)` ([RFC 9171 Section 4.2.2](https://www.rfc-editor.org/rfc/rfc9171.html#section-4.2.2)) eliminates any need to add an ad-hoc hash.
- **Breaking Transitivity Loops:** Even if transitivity creates temporary probabilistic oscillations between two groups of nodes, the **Hop Count Block (Type 10)** guarantees that the bundle will be dropped immediately once `hop_count >= hop_limit`.

### 3.4. Encounter Protocol: CDDL Specification of Control Messages ([prophet.cddl](./prophet.cddl))

A fundamental observation distinguishes PRoPHET from previous protocols: **PRoPHET is the very first algorithm in our series that explicitly requires a bilateral information exchange protocol between nodes upon contact.**
- In APRS, stations digipeat UI frames blindly without any acknowledgement or table synchronization.
- In Meshtastic, nodes flood the LoRa channel without prior negotiation.
- In Spray & Wait, rationing is calculated locally by mathematical division of quota $L$.

Conversely, as soon as two PRoPHET nodes $A$ and $B$ discover each other, they must exchange two vital categories of information:
1. **The Routing Information Base (RIB Update):** Peer $B$'s predictability vector $P_{(B, *)}$, essential for $A$ to update its transitive scores and determine if $P_{(B, D)} > P_{(A, D)}$.
2. **The Summary Vector (SV):** The inventory of bundle IDs that each node already holds, to prevent replicating bundles already held by the peer.
3. **The Combined Handshake:** A critical optimization for constrained radio links (LoRa / AX.25), merging RIB and Summary Vector into **a single CBOR message**.
4. **Delivery ACKs:** Final delivery notifications enabling the proactive purging of redundant replicas in network memory buffers.

In DTN, these signaling messages can be transported either at the convergence layer (CLA) session level or directly encapsulated inside the **payload of an administrative bundle** (e.g. addressed to `dtn://contact-peer/prophet`).

The file **[prophet.cddl](./prophet.cddl)** rigorously formalizes this CBOR grammar:

```cddl
prophet-control-bundle = {
    1 => message-type: prophet-message-type,
    2 => sender-eid: tstr,                  ; Sender EID
    3 => timestamp-ms: uint,                ; Emission DTN timestamp
    ? 4 => payload: prophet-message-payload ; Message payload
}

; Radio optimization: Combined Handshake (RIB + Summary Vector)
handshake-combined-payload = {
    1 => rib-entries: [* rib-entry],        ; (destination_eid, P_value) pairs
    2 => held-bundles: [* bundle-identifier], ; Canonical identifiers (source, time, seq)
    ? 3 => available-storage-bytes: uint    ; Remaining storage space
}

rib-entry = {
    1 => destination-eid: tstr,
    2 => delivery-predictability: float,
    ? 3 => last-update-dtn-time: uint
}
```

#### How this exchange feeds the OPA engine
The DTN daemon receives this control administrative bundle, decodes the CBOR payload, updates its transitivity table, and injects data directly into the OPA context:
- `rib-entries` populates `input.contact.peer_predictabilities`.
- `held-bundles` populates `input.contact.held_bundle_ids`.

This separation is remarkable: **the transport plane exchanges the control bundles described in [prophet.cddl](./prophet.cddl), while the OPA engine evaluates declarative rules in [contact.rego](./policies/prophet/contact.rego) in complete isolation.**

---

## 4. Declarative Implementation with OPA (Rego)

The policy suite is organized in the folder [policies/prophet/](./policies/prophet/).

### 4.1. Mathematical Helper Functions ([helpers.rego](./policies/prophet/helpers.rego))

Because Rego forbids infinite recursion to guarantee termination, aging and transitivity are computed using a closed form:

```rego
package dtn.prophet.helpers

# Direct encounter: P(a, b) = P(a, b)_old + (1 - P(a, b)_old) * P_encounter
update_encounter(p_old, p_encounter) := p_new if {
    p_new := p_old + ((1.0 - p_old) * p_encounter)
}

# Non-recursive temporal decay: gamma ^ k
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

# Transitivity: P(a, c) = P(a, c)_old + (1 - P(a, c)_old) * P(a, b) * P(b, c) * beta
update_transitivity(p_ac_old, p_ab, p_bc, beta) := p_ac_new if {
    transitive_factor := (p_ab * p_bc) * beta
    p_ac_new := p_ac_old + ((1.0 - p_ac_old) * transitive_factor)
}
```

### 4.2. Forwarding Rule Upon Contact ([contact.rego](./policies/prophet/contact.rego))

When a CLA link is established with neighbour $B$:
1. If $B$ is the bundle's final destination $\implies$ `FORWARD_DIRECT`.
2. If $B$ already holds the bundle (Summary Vector check) $\implies$ `SKIP`.
3. If the bundle carries an `opportunistic_threshold` and $P_{(B, D)} < \text{threshold}$ $\implies$ `SKIP`.
4. **Fundamental PRoPHET Condition:**  
   If $P_{(B, D)} > P_{(A, D)} + \Delta_\text{margin}$ $\implies$ `FORWARD_OPPORTUNISTIC`.  
   The local node transmits a replica to peer $B$, as the latter presents a statistically superior probability of delivering the bundle safely.

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

### 4.3. Buffer Management and Storage Eviction ([storage.rego](./policies/prophet/storage.rego))

In persistent Store-Carry-and-Forward networks, disks and Flash memories rapidly become congested. Section 3.4 of RFC 6693 recommends an eviction strategy guided by $P_{(A, D)}$:

> *During buffer overflows, a PRoPHET node should preferentially eliminate bundles for which it has the lowest local delivery predictability $P_{(A, D)}$.*

This rule is expressed in OPA:

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

## 5. Validation via OPA Unit Tests (60/60 PASS)

A suite of 16 unit tests specific to PRoPHET ([prophet_test.rego](./policies/prophet/prophet_test.rego)) was added. It covers:
- Accuracy of mathematical formulas (encounter, transitivity, temporal decay).
- Ingress admission and rejection behavior.
- Summary Vector and sender utility threshold filtering.
- Opportunistic forwarding decision between carrier and contact.
- Selective bundle eviction during memory saturation.

Running the full repository test suite:

```bash
opa test ./policies -v
```

```text
policies/aprs/aprs_test.rego:
  13 validated tests (AX.25 digipeating, Dire Wolf rules 6.1b, 6.3c, §10 trapping)
policies/contact_test.rego:
  5 validated tests (CLA contact foundations, split-horizon, lifetime)
policies/flood/flood_test.rego:
  17 validated tests (binary/source Spray & Wait, Meshtastic SNR backoff and contention)
policies/ingress_test.rego:
  6 validated tests (ingress foundations, Hop Count Type 10, source blacklisting)
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
  3 validated tests (Bundle Age Block Type 7 management)
--------------------------------------------------------------------------------
PASS: 60/60
```

---

## 6. Comparative Synthesis: Epidemic vs Spray & Wait vs PRoPHET

| Criterion | Epidemic ([Article 2](./article-2-flood.en.md)) | Spray and Wait ([Article 2](./article-2-flood.en.md)) | PRoPHET ([RFC 6693](https://www.rfc-editor.org/rfc/rfc6693.html)) |
| :--- | :--- | :--- | :--- |
| **Topological Knowledge** | None (blind) | None (blind) | Local encounter history and transitivity |
| **Copy Dissemination** | Unbounded flooding | Bounded to $L$ strict copies | Guided by utility differential $P_{(B, D)} > P_{(A, D)}$ |
| **Delivery Rate in Dense Networks** | Poor (saturation & drops) | Good | Excellent (favors central nodes) |
| **Bandwidth Overhead** | Very high | Low ($L-1$ transmissions) | Moderate (selective forwarding) |
| **Buffer Overflow Management** | Drop-Tail (random / FIFO) | FIFO / age | Targeted eviction of low-predictability bundles |

---

## 7. Outlook: Toward Theoretical Optimality and Buffer Management (MaxProp)

With PRoPHET, we have reached a decisive milestone: routing no longer suffers topology by chance, it adapts dynamically to the real habits of mobile entities.

In the next article ([Article 4 — MaxProp](./article-4-maxprop.en.md)), we will take another step forward: how to rigorously schedule transmission and eviction queues under buffer congestion, transform contact probabilities into optimal logarithmic information cost ($-\log(P + \epsilon)$), and adapt topological gossip to constrained radio channels (2-Hop Gossip).

---

👉 **Next article:** [Article 4 — Probabilistic Routing and Memory Management under Constraints: MaxProp and its Theoretical Optimizations (HP-MaxProp)](./article-4-maxprop.en.md)
