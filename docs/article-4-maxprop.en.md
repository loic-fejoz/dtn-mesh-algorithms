# Article 4 — Probabilistic Routing and Memory Management under Constraints: MaxProp and its Theoretical Optimizations (HP-MaxProp)

> **Series:** *Porting Mesh & Opportunistic Routing Algorithms to DTN (BPv7)*  
> **Previous articles:**  
> - [Article 0 — Foundations of DTN Routing with Open Policy Agent](./article-0-intro.en.md)  
> - [Article 1 — Porting APRS Digipeating (AX.25 WIDE n-N) to DTN (BPv7)](./article-1-aprs.en.md)  
> - [Article 2 — Taming Flooding in DTN: From Epidemic to Spray and Wait and Meshtastic Managed Flooding](./article-2-flood.en.md)  
> - [Article 3 — Opportunistic Routing and Encounter History: PRoPHET (RFC 6693) under Open Policy Agent](./article-3-prophet.en.md)  
> **Next articles:**  
> - [Article 5 — Hybrid Routing, Distance Vector and Cryptographic Addressing: Reticulum (RNS) Transposed to DTN](./article-5-reticulum.en.md)  
> - [Article 6 — Proactive Mesh Networks and MANET-DTN Hybridization: AREDN, Babel (RFC 8966) and the HYMAD Architecture under Open Policy Agent](./article-6-babel-aredn.en.md)  
> **CDDL Specifications:** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl), [prophet.cddl](./prophet.cddl) & [maxprop.cddl](./maxprop.cddl)  
> **Policy Code:** [policies/maxprop/](./policies/maxprop/) ([ingress.rego](./policies/maxprop/ingress.rego), [contact.rego](./policies/maxprop/contact.rego), [storage.rego](./policies/maxprop/storage.rego), [helpers.rego](./policies/maxprop/helpers.rego), [constants.rego](./policies/maxprop/constants.rego), [maxprop_test.rego](./policies/maxprop/maxprop_test.rego))

> ℹ️ **Editorial Transparency Note (EU AI Act Alignment):** This article was generated with AI assistance under the editorial direction and structuring of a human author, who assumes responsibility for its technical review, verification, and content (ongoing proofreading).

---

## 1. The Gordian Knot of DTN: Buffer Saturation

In [Article 3](./article-3-prophet.en.md), we modeled **PRoPHET (RFC 6693)**, where the decision to relay a bundle depends on the probabilistic gain brought by a contact ($P_{(B, D)} > P_{(A, D)}$).

However, in any delay-tolerant network deployed in the real world (vehicular networks, off-grid emergency response, LEO microsatellite constellations, or wildlife sensors), one resource rapidly becomes the fatal bottleneck: **the storage buffer and contact bandwidth**.
- Radio visibility windows between two mobile nodes are brief (seconds to minutes).
- A node may accumulate hundreds of megabytes of pending data.
- If a node can transmit only a subset of its bundles before the link drops, **which ones should it send first?**
- If memory saturates (*buffer overflow*), **which bundles should it sacrifice first?**

To address this dual problem of scheduling and eviction, the benchmark algorithm in DTN literature is **MaxProp**, designed by John Burgess, Brian Gallagher, David Bissias, James F. Levine, and Brian Lynn (UMass Amherst, 2006).

---

## 2. Foundations of Classic MaxProp

MaxProp structures opportunistic routing around four fundamental pillars:

```
       +-------------------------------------------------------------+
       | 1. Topological Gossip: Probability vectors                  |
       |    Regular exchange of inter-node encounter histories       |
       +-------------------------------------------------------------+
                                      |
                                      v
       +-------------------------------------------------------------+
       | 2. Dijkstra Shortest Path Computation                       |
       |    Evaluation of global transfer cost to target             |
       +-------------------------------------------------------------+
                                      |
                                      v
       +-------------------------------------------------------------+
       | 3. Bidirectional Queue Scheduling                           |
       |    - Send priority for most likely paths                    |
       |    - Eviction of most costly / heavily replicated packets   |
       +-------------------------------------------------------------+
                                      |
                                      v
       +-------------------------------------------------------------+
       | 4. Acknowledgement Propagation: Cleared List                |
       |    Proactive purging of replicas delivered to destination   |
       +-------------------------------------------------------------+
```

### 2.1. Probability Exchange and Dijkstra Tree
Each node $i$ maintains a vector of contact probabilities with all other nodes $j$ in the network, normalized such that $\sum_j P_{i, j} = 1$.
When a contact is established, nodes exchange their probability matrices, enabling each entity to reconstruct a weighted network graph and execute Dijkstra's algorithm to determine the cumulative path cost to any destination.

### 2.2. The Cleared List (ACK Distribution)
As soon as a bundle reaches its final destination, the latter emits an acknowledgement notification embedded in a structure called the **`Cleared List`**.
This list of delivered bundles is propagated by gossip at every encounter: as soon as an intermediate node receives the `Cleared List`, it **immediately deletes all corresponding replicas from its storage**, instantly freeing space for packets still in transit.

---

## 3. The Two Heuristic Weaknesses of MaxProp and Their Mathematical Resolution (HP-MaxProp)

Although MaxProp demonstrated remarkable performance in *The ONE* simulator, a rigorous mathematical analysis highlights two suboptimal approximations in its original formulation.

### 3.1. From Linear Cost to Logarithmic Information Optimality
In original MaxProp, link cost assigned to a transition between two nodes with encounter probability $P$ is modeled by a naive linear function:
$$\text{Linear Cost} = 1 - P$$

This formulation is mathematically flawed when evaluating a multi-hop path. In probability theory, the joint independent delivery probability along a path $A \to B \to C$ is **multiplicative**:
$$P(A \to C) = P(A \to B) \times P(B \to C)$$

To transform this probability product into a sum minimizable by Dijkstra's algorithm, information theory (Shannon) mandates the use of the **negative logarithm**:
$$\text{Link Cost} = -\log(P + \epsilon)$$
*(where $\epsilon \approx 0.001$ is a residual constant preventing divergence to infinity when $P = 0$)*.

Thanks to this transformation, the sum of costs along a path computed by Dijkstra rigorously minimizes:
$$\sum_{i} \text{Cost}_i = \sum_{i} -\log(P_i + \epsilon) = -\log\left(\prod_i (P_i + \epsilon)\right)$$
Which is equivalent to **mathematically maximizing the overall delivery probability**!

### 3.2. From Binary Hop Threshold to Smooth Hop Penalty
To order its queue, MaxProp seeks to prioritize rare packets (which have few copies in circulation) over widely disseminated packets.
In the historical algorithm, this is achieved via a **binary Hop Threshold**:
- Packets having traveled fewer than $N$ hops (for example $N = 3$) are all placed at the front of the queue (sorted by Dijkstra cost).
- As soon as a packet reaches $N$ hops, it is abruptly demoted to the second half of the queue.

This binary discontinuity arbitrarily penalizes viable packets. A much smoother approach consists of introducing a **continuous hop penalty** into the sorting cost:
$$\text{Sorting Cost} = \text{Dijkstra Cost} + 0.01 \times \text{HopCount}$$

The factor $\alpha = 0.01$ subtly balances structural path quality (estimated by Dijkstra) and bundle age/rarity (estimated by its `Hop Count`). A rare packet with a slightly less optimal path will remain prioritized over a packet that has already saturated 10 intermediate relays.

### 3.3. Radio Bottleneck: The 2-Hop Alternative for Constrained Channels (LoRa / AX.25)
Gossiping full probability matrices of size $O(N^2)$ is feasible over 54 Mbps Wi-Fi between urban buses (as in the initial UMass DieselNet experiment). But over a LoRa network (1-2 kbps) or AX.25 packet radio (1200 baud), this protocol overhead would choke the channel.

The **2-Hop MaxProp (2H-HP-MaxProp)** optimization eliminates the transitive exchange of third-party tables:
- Nodes exchange only their **own direct contact vector** ($O(N)$ complexity instead of $O(N^2)$).
- Each node evaluates Dijkstra over a local 2-hop horizon.
- This reduction removes over **99% of signaling overhead**, while preserving most of the delivery efficiency in constrained environments.

> [!NOTE]
> **Terminological Precision on "HP-MaxProp":**  
> The term "HP-MaxProp" (*High-Performance MaxProp*) is a designation specific to this series of articles to describe the triptych of theoretical optimizations (logarithmic information cost $-\log(P+\epsilon)$, continuous hop penalty $+0.01 \times \text{HopCount}$, and local 2-hop gossip $O(N)$) brought to the original algorithm by Burgess et al. (2006).

---

## 4. CDDL Wire Specification: `maxprop.cddl`

As with our other protocols, **data bundles circulate in pure standard BPv7 without any proprietary wire block**.

Inter-node signaling (probability vector and acknowledgement list) is formalized in CBOR in **[maxprop.cddl](./maxprop.cddl)**:

```cddl
; MaxProp control message carried in the payload of an administrative bundle
maxprop-control-bundle = {
    1 => message-type: maxprop-message-type,
    2 => sender-eid: tstr,                  ; Sender node EID
    3 => timestamp-ms: uint,                ; Emission DTN timestamp
    4 => payload: maxprop-payload           ; Payload according to type
}

maxprop-message-type = &(
    msg-prob-vector: 1,   ; Direct contact probability vector (O(N))
    msg-cleared-list: 2,  ; List of delivered bundles to purge (Cleared List)
    msg-combined: 3       ; Combined message (Probabilities + Cleared List)
)

; Cleared List: inventory of acknowledged bundles
cleared-list-payload = {
    1 => cleared-bundle-ids: [ * canonical-bundle-id ]
}

canonical-bundle-id = [
    source-eid: tstr,
    creation-time: uint,
    sequence-number: uint
]
```

The **canonical Bundle ID** `(source, time, sequence)` defined in [RFC 9171 Section 4.2.2](https://www.rfc-editor.org/rfc/rfc9171.html#section-4.2.2) naturally serves as a universal unique key in the `cleared_list`.

---

## 5. Declarative Modeling under Open Policy Agent (OPA)

The directory **[policies/maxprop/](./policies/maxprop/)** formalizes the entirety of MaxProp decision logic.

### 5.1. Ingress: Acknowledgement Ingestion and Sorting Cost Computation ([ingress.rego](./policies/maxprop/ingress.rego))

At ingress, OPA applies two crucial filters:
1. **Preventive Rejection of Acknowledged Bundles:** If an incoming bundle appears in the local `cleared_list`, it is immediately dropped without consuming memory.
2. **HP-MaxProp Sorting Metric Computation:** For every accepted bundle, OPA computes its sorting cost and attaches it as internal metadata.

```rego
# Ingress Rule 4: Drop if present in Cleared List
decision := {
    "action": "DROP",
    "reason": "Bundle already acknowledged in Cleared List",
    "generate_status_report": false,
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
}

# Ingress Rule 9: Data bundle — HP-MaxProp sorting cost computation
decision := {
    "action": "ACCEPT_FORWARD",
    "reason": sprintf("Data bundle accepted: HP-MaxProp sorting cost computed (%v)", [sorting_cost]),
    "mutations": [
        {
            "block_type": base_constants.block_type_hop_count,
            "operation": "SET_FIELD",
            "field": "hop_count",
            "value": hcb.hop_count + 1
        },
        {
            "operation": "SET_SORTING_COST",
            "sorting_cost": sorting_cost
        }
    ]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    canonical_id := base_helpers.get_bundle_id(input.bundle)
    not canonical_id in object.get(input.node, "seen_cache", [])
    not helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    not helpers.is_maxprop_control(input.bundle)
    hcb := base_helpers.get_hop_count_block(input.bundle)
    dijkstra_cost := object.get(input.bundle, "dijkstra_cost", 1.0)
    sorting_cost := helpers.compute_sorting_cost(dijkstra_cost, hcb.hop_count + 1)
}
```

### 5.2. Contact: Dijkstra-Guided Opportunistic Forwarding ([contact.rego](./policies/maxprop/contact.rego))

When a contact is established with a peer, the decision to forward a bundle depends on the path cost differential:
- If the peer has a path cost to the destination **strictly lower** than ours ($Cost_{peer \to D} < Cost_{me \to D}$), the bundle is transmitted with its sorting priority.
- If the peer has an equal or higher cost, it is skipped (`SKIP`).

```rego
# Contact Rule 7: Favorable opportunistic forward
decision := {
    "action": "FORWARD_FAVORABLE",
    "reason": sprintf("Peer %v has lower Dijkstra path cost to %v (%v < %v)", [
        input.contact.peer_eid,
        input.bundle.primary.destination,
        peer_cost,
        my_cost
    ]),
    "mutations": [{
        "operation": "SET_PRIORITY_COST",
        "sorting_cost": sorting_cost
    }]
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_maxprop_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    not helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
    canonical_id := base_helpers.get_bundle_id(input.bundle)
    not canonical_id in object.get(input.contact, "held_bundle_ids", [])
    
    dest := input.bundle.primary.destination
    my_cost := helpers.get_path_cost(dest, object.get(input.node, "path_costs", {}))
    peer_cost := helpers.get_path_cost(dest, object.get(input.contact, "peer_path_costs", {}))
    peer_cost < my_cost
    
    hcb := base_helpers.get_hop_count_block(input.bundle)
    sorting_cost := helpers.compute_sorting_cost(my_cost, hcb.hop_count)
}
```

### 5.3. Storage: Cleared List Purging and Targeted Eviction ([storage.rego](./policies/maxprop/storage.rego))

In the storage manager:
1. **Instant Purge:** Any bundle identified in the local `cleared_list` is immediately deleted (`PURGE_CLEARED`).
2. **Selective Eviction Under Memory Congestion:** When the buffer is saturated (`buffer_full == true`), bundles with a sorting cost $\text{Sorting Cost}$ exceeding the eviction threshold are removed (`EVICT_LOW_PRIORITY`).

```rego
# Storage Rule 4: Selective eviction upon storage saturation
decision := {
    "action": "EVICT_LOW_PRIORITY",
    "reason": sprintf("Buffer congestion: evicting bundle with high sorting cost (%v >= threshold %v)", [
        sorting_cost,
        threshold
    ]),
    "generate_status_report": base_helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
    object.get(input.node, "buffer_full", false) == true
    threshold := object.get(input.node, "eviction_cost_threshold", 5.0)
    
    hcb := base_helpers.get_hop_count_block(input.bundle)
    dijkstra_cost := object.get(input.bundle, "dijkstra_cost", 1.0)
    sorting_cost := helpers.compute_sorting_cost(dijkstra_cost, hcb.hop_count)
    sorting_cost >= threshold
}
```

---

## 6. Validation via OPA Unit Tests (76/76 PASS)

A suite of 16 specific unit tests ([policies/maxprop/maxprop_test.rego](./policies/maxprop/maxprop_test.rego)) covers all scenarios:
- Admission and exact sorting cost computation $\text{Sorting Cost} = \text{Dijkstra} + 0.01 \times \text{HopCount}$.
- Ingestion of probability vectors and acknowledgement lists (`Cleared List`).
- Preventive rejection and purging of delivered bundles.
- Opportunistic arbitration based on Dijkstra path cost differential.
- Selective eviction of most costly packets under storage buffer congestion.

Running the full repository test suite:

```bash
opa test ./policies -v
```

```text
policies/aprs/aprs_test.rego:           13 validated tests
policies/contact_test.rego:              5 validated tests
policies/flood/flood_test.rego:         17 validated tests
policies/ingress_test.rego:              6 validated tests
policies/maxprop/maxprop_test.rego:     16 validated tests
policies/prophet/prophet_test.rego:     16 validated tests
policies/storage_test.rego:              3 validated tests
--------------------------------------------------------------------------------
PASS: 76/76
```

---

## 7. Comparative Synthesis: PRoPHET vs MaxProp

| Criterion | PRoPHET ([Article 3](./article-3-prophet.en.md)) | MaxProp / HP-MaxProp ([Article 4](./article-4-maxprop.en.md)) |
| :--- | :--- | :--- |
| **Contact Metric** | Scalar predictability $P_{(A, B)} \in [0, 1]$ | Normalized transition probabilities $\sum P_{i, j} = 1$ |
| **Information Propagation** | Transitivity equations ($\beta$) | Dijkstra shortest path tree ($-\log(P + \epsilon)$) |
| **Rarity Consideration** | Indirect (via sender threshold) | **Smooth hop penalty** ($+ 0.01 \times \text{HopCount}$) |
| **Delivered Data Purging** | Optional (Delivery ACK) | **Systematic Cleared List** distributed by gossip |
| **Buffer Eviction Scheduling** | Eviction by lowest predictability | **Eviction by highest sorting cost** (worst path + heavy replication) |
| **Radio Overhead** | Moderate (local RIB) | $O(N)$ in 2H-HP-MaxProp (ideal for radio/LoRa) vs $O(N^2)$ in classic |

---

## 8. Outlook: Toward Cryptographic Ad-Hoc Networks (Reticulum)

With PRoPHET and MaxProp, we have explored how to mathematically exploit encounter histories and information theory to maximize delivery ratios while intelligently managing storage buffers.

In the next article ([Article 5](./article-5-reticulum.en.md)), we will take another step toward network sovereignty: **Reticulum (RNS)**, a distance-vector routing protocol based on 16-byte self-sovereign cryptographic addresses, signed announcements, and a zero-IP architecture free of central coordination.

---

👉 **Next article:** [Article 5 — Hybrid Routing, Distance Vector and Cryptographic Addressing: Reticulum (RNS) Transposed to DTN](./article-5-reticulum.en.md)
