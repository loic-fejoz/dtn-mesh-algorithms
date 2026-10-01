# Article 2 — Taming Flooding in DTN: From Epidemic to Spray and Wait and Meshtastic Managed Flooding

> **Series:** *Porting Mesh & Opportunistic Routing Algorithms to DTN (BPv7)*  
> **Previous articles:**  
> - [Article 0 — Foundations of DTN Routing with Open Policy Agent](./article-0-intro.en.md)  
> - [Article 1 — Porting APRS Digipeating (AX.25 WIDE n-N) to DTN (BPv7)](./article-1-aprs.en.md)  
> **CDDL Specification:** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl)  
> **Policy Code:** [policies/flood/](./policies/flood/) ([ingress.rego](./policies/flood/ingress.rego), [contact.rego](./policies/flood/contact.rego), [helpers.rego](./policies/flood/helpers.rego), [constants.rego](./policies/flood/constants.rego), [flood_test.rego](./policies/flood/flood_test.rego))

> ℹ️ **Editorial Transparency Note (EU AI Act Alignment):** This article was generated with AI assistance under the editorial direction and structuring of a human author, who assumes responsibility for its technical review, verification, and content (ongoing proofreading).

---

## 1. The Fundamental Tension of Flooding in Constrained Networks

In Delay-Tolerant Networks (DTN) and infrastructureless ad-hoc mesh networks, routing faces a constant dilemma between:
1. **Minimizing delivery latency** to the destination.
2. **Preserving critical resources**: battery energy, memory buffer occupancy, and radio spectrum duty cycle (LoRa duty cycle, CSMA collisions).

### 1.1. The Illusion of Epidemic Routing
Introduced by Vahdat and Becker in 2000, **Epidemic Routing** relies on blind opportunistic flooding: as soon as two nodes meet, they exchange all bundles they do not yet share in common.
- **Theoretical Advantage:** In an ideal network with unlimited memory and bandwidth, Epidemic mathematically guarantees minimal delivery latency (*optimal delay*), as it simultaneously explores all possible physical paths.
- **Practical Disaster:** As soon as traffic volume increases, queues saturate. The network collapses under broadcast storms and massive packet drops due to buffer overflow (*drop-tail*).

To overcome this limitation, two major philosophies have emerged:
- **Spatio-temporal and Radio Arbitrage (Meshtastic):** Restrict the propagation radius via a strict `hop_limit`, deduplicate aggressively, and introduce a contention window inversely proportional to the radio signal quality (SNR).
- **Strict Quota Rationing (Spray and Wait):** Bound a priori the maximum number $L$ of copies allowed to circulate in the entire network, eliminating any risk of uncontrolled exponential proliferation.

---

## 2. Algorithm Breakdown

### 2.1. Spray and Wait (Spyropoulos, Psounis, Raghavendra)
To remedy the excesses of Epidemic while maintaining great simplicity, Spray and Wait divides the lifecycle of a bundle into two distinct phases:

```
             [ Source sender: Quota L copies ]
                               |
                               v
                      +-------------------+
                      |    SPRAY Phase    |  (L > 1)
                      +-------------------+
                               |
            +------------------+------------------+
            |                                     |
    (Source Spray)                         (Binary Spray)
  Gives 1 copy per relay,                Gives floor(L/2) copies,
  retains (L - 1) copies                 keeps ceil(L/2) copies
            |                                     |
            +------------------+------------------+
                               |
                               v
                      +-------------------+
                      |    WAIT Phase     |  (L == 1)
                      +-------------------+
                               |
             (Intermediate relay forbidden!)
            Passive wait for final destination
```

#### A. Source Spray vs Binary Spray
- **Source Spray:** Only the source node distributes copies. As soon as it encounters a relay node that does not possess the bundle, it transmits 1 copy to it (which immediately enters the *Wait* phase with $L=1$). The source decrements its local quota by 1.
- **Binary Spray:** Any node holding $L > 1$ copies can replicate. When it encounters a node without a copy, it transfers $\lfloor L / 2 \rfloor$ copies to it and retains $\lceil L / 2 \rceil$ copies. This binary distribution is significantly faster than Source Spray, as the dissemination effort is shared exponentially among carriers.

#### B. The Wait Phase ($L = 1$)
As soon as a carrier retains only a single copy ($L = 1$), it transitions to the **Wait** phase. It is **strictly forbidden** from transmitting the bundle to any intermediate relay. It carries the bundle until directly encountering the final destination Endpoint (`contact.peer_eid == destination`).

---

### 2.2. Meshtastic Managed Flooding
Designed for ESP32/nRF52 microcontrollers operating on the 868/915 MHz ISM band with LoRa modulation, Meshtastic applies a flooding mechanism highly optimized for low-bitrate radio:

1. **Deduplication Table (*Seen Cache*):** Each frame carries a 32-bit `packet_id`. Any packet already received within a sliding time window is immediately dropped at ingress.
2. **Channel Segregation (*Channel Hash*):** The packet is filtered according to a channel hash (e.g., default public channel vs encrypted private channel).
3. **SNR-Weighted Contention Window (*SNR-based backoff*):**  
   When a node receives a packet to be relayed over radio broadcast, it does not retransmit immediately. It computes a backoff delay:
   $$\text{Backoff}(SNR) = \text{BaseDelay} + \text{Factor} \times \max(0, SNR_{\text{dB}} + 15)$$
   - **Distant Node (low SNR, e.g., -10 dB):** Receives a **short** backoff delay. It retransmits first to propagate the packet as far as possible.
   - **Nearby Node (high SNR, e.g., +10 dB):** Receives a **long** backoff delay.
   - **Listen-based Cancellation (*Contention Cancel*):** If, during its backoff interval, the nearby node hears the packet being retransmitted by a peer, it **cancels its own transmission**. This eliminates redundant echoes between geographically adjacent nodes!

---

## 3. CDDL Specification and Radical Streamlining: Spray & Wait and Meshtastic

The file [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl) integrates the required primitives under experimental block type `200`:

```cddl
; Modular and agnostic BPv7 experimental block (Type 200)
mesh-routing-data = {
    ? 1 => legacy-bridge-id: (bytes / uint), ; Optional external fingerprint (LoRa gateway)
    ? 2 => replication-control,              ; Rationing and quota primitives
    ...
}

; Replication Dimension (used by Spray & Wait, MaxProp, etc.)
replication-control = {
    1 => quota: uint,                        ; Assigned copy quota L
    ? 2 => mode: &(mode-source: 1, mode-binary: 2), ; Unitary or binary distribution
    ? 3 => phase: &(phase-disseminate: 1, phase-wait: 2), ; Active phase
    ? 4 => generation: uint                  ; Generation / replication level
}
```

### 3.1. Architectural Reconciliation: Hop Count Block (Type 10) and Universal Bundle ID

Two major simplifications were identified during our modeling:

1. **The Meshtastic hop limit is 100% isomorphic to the Hop Count Block (Type 10):**  
   Meshtastic uses `hop_start` (the initial value) and `hop_limit` (decremented at each hop). In RFC 9171, the **Hop Count Block (Type 10)** uses `hop_limit` and `hop_count`.  
   The equivalence is absolute: $\text{hop\_start} = \text{hop\_limit}_{\text{Type 10}}$ and the remaining hop count under Meshtastic is $\text{hop\_limit} - \text{hop\_count}$.  
   By reusing the standard Type 10 block, **any conventional DTN router** (even those without Meshtastic LoRa logic) immediately halts packet propagation if it exceeds its limit!

2. **The Redundancy of `packet-id` and `message-id`:**  
   While Meshtastic and Spray & Wait each define a packet or message identifier for their deduplication tables or Summary Vectors, the **canonical Bundle ID** `(source_eid, creation_time, sequence_number)` from RFC 9171 Section 4.2.2 natively and universally fulfills this purpose. No ad-hoc identifier needs to be carried in the extension block in native DTN.

### 3.2. Why `channel_id` Was Removed: Radio Channel is Not a BPv7 Metadata

An in-depth architectural reflection led us to eliminate any radio channel field (`wireless-channel` / `channel_id`) from the wire extension block:
- **Layering Violation:** The Bundle Protocol is an overlay network. A LoRa channel or radio frequency are Layer 1 / 2 (PHY / Data Link) properties. If a bundle traverses a satellite link or a TCPCL tunnel between two cities, a local radio channel identifier loses all meaning.
- **Application-Level EID Filtering (Whitelist):** In Meshtastic, channel segregation serves to filter traffic that the node does not wish to relay. In DTN, this is expressed much more elegantly and universally via a **whitelist of destination EID patterns** (`input.node.allowed_destinations`, e.g., `dtn://channels/emergency/*`) or directly at the ingress CLA adapter level.

### 3.3. Major Takeaway: Meshtastic Operates in Pure Standard BPv7!

This reasoning leads to a remarkable conclusion: **Meshtastic managed flooding requires no proprietary extension block over the air!**
- Propagation radius control relies on the standard **Hop Count Block (Type 10)**.
- Deduplication relies on the standard **canonical BPv7 Bundle ID**.
- Traffic segregation relies on **standardized EIDs**.
- Contention backoff calculation ($Backoff(SNR)$) and listen-based cancellation are **purely local orchestration decisions**, offloaded to the OPA engine via ingress telemetry (`input.ingress.snr_db`) and internal state (`input.node.cancelled_rebroadcasts`).

---

## 4. Declarative Implementation with OPA (Rego)

All rules are implemented in [policies/flood/](./policies/flood/).

### 4.1. Mathematical Helper Functions ([helpers.rego](./policies/flood/helpers.rego))

```rego
package dtn.flood.helpers

# Quota binary split for Spray & Wait
calculate_binary_spray(quota) := result if {
    quota >= 2
    to_send := floor(quota / 2)
    to_keep := quota - to_send
    result := {
        "send_quota": to_send,
        "keep_quota": to_keep,
        "new_local_phase": phase_for_quota(to_keep),
        "transmitted_phase": phase_for_quota(to_send)
    }
}

# Meshtastic contention calculation
calculate_meshtastic_backoff(snr_db) := delay_ms if {
    clamped_snr := max([snr_db + 15, 0])
    delay_ms := constants.meshtastic_base_backoff_ms + round(clamped_snr * constants.meshtastic_snr_factor_ms)
}
```

### 4.2. Ingress Policy ([ingress.rego](./policies/flood/ingress.rego))

1. **Universal Deduplication:** Immediate drop if the bundle identifier has already been seen.
2. **Ingress Spray & Wait:** Records the bundle and initializes the phase (`SPRAY` if $L > 1$, `WAIT` if $L = 1$).
3. **Ingress Meshtastic:**
   - Verifies compliance of `channel_hash` with the local node's channel.
   - Computes rebroadcast backoff delay according to reception SNR and instructs it via CBOR mutation.

### 4.3. Contact Policy ([contact.rego](./policies/flood/contact.rego))

Decision-making during a CLA contact opportunity faithfully reflects the theoretical rules:

```rego
# 1. Direct contact with destination: immediate delivery without conditions
decision := {
    "action": "FORWARD_DIRECT",
    "reason": "Peer is the destination endpoint",
    "mutations": []
} if {
    input.contact.peer_eid == input.bundle.primary.destination
}

# 2. Strict prohibition of forwarding a WAIT phase bundle to an intermediate relay
decision := {
    "action": "SKIP",
    "reason": "Spray & Wait bundle is in WAIT phase (L=1): awaiting direct destination contact only",
    "mutations": []
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    block := helpers.get_spray_block(input.bundle)
    not helpers.peer_already_holds_bundle(input.contact, block.payload.message_id)
    block.payload.replication_quota <= 1
}

# 3. Replication in Binary Spray mode
decision := {
    "action": "FORWARD_REPLICATE",
    "reason": sprintf("Binary spray: splitting quota L=%v", [block.payload.replication_quota]),
    "mutations": [{
        "block_type": constants.block_type_mesh_routing,
        "operation": "MUTATE_SPRAY_QUOTA",
        "local_quota": split.keep_quota,
        "local_phase": split.new_local_phase,
        "transmitted_quota": split.send_quota,
        "transmitted_phase": split.transmitted_phase
    }]
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    block := helpers.get_spray_block(input.bundle)
    not helpers.peer_already_holds_bundle(input.contact, block.payload.message_id)
    block.payload.replication_quota >= 2
    block.payload.spray_mode == constants.spray_mode_binary
    split := helpers.calculate_binary_spray(block.payload.replication_quota)
}

# 4. Meshtastic cancellation if heard during backoff
decision := {
    "action": "SKIP",
    "reason": "Meshtastic rebroadcast cancelled: packet heard from another peer during backoff",
    "mutations": []
} if {
    block := helpers.get_meshtastic_block(input.bundle)
    block.payload.packet_id in object.get(input.node, "cancelled_rebroadcasts", [])
}
```

---

## 5. Validation via OPA Unit Tests (44/44 PASS)

The dedicated unit test suite ([flood_test.rego](./policies/flood/flood_test.rego)) validates 17 critical scenarios, bringing the repository total to **44 successfully validated tests**:

```bash
opa test ./policies -v
```

```text
./policies/flood/flood_test.rego:
data.dtn.flood_test.test_flood_local_delivery: PASS (602µs)
data.dtn.flood_test.test_flood_duplicate_suppression: PASS (1.66ms)
data.dtn.flood_test.test_spray_ingress_spray_phase: PASS (1.82ms)
data.dtn.flood_test.test_spray_ingress_wait_phase: PASS (1.53ms)
data.dtn.flood_test.test_spray_contact_direct_destination: PASS (504µs)
data.dtn.flood_test.test_spray_contact_skip_peer_already_holds: PASS (1.02ms)
data.dtn.flood_test.test_spray_contact_binary_split_even: PASS (3.27ms)
data.dtn.flood_test.test_spray_contact_binary_split_to_wait: PASS (2.40ms)
data.dtn.flood_test.test_spray_contact_source_spray: PASS (1.80ms)
data.dtn.flood_test.test_spray_contact_wait_phase_skip_relay: PASS (1.26ms)
data.dtn.flood_test.test_meshtastic_ingress_channel_match_and_backoff: PASS (3.76ms)
data.dtn.flood_test.test_meshtastic_ingress_channel_mismatch: PASS (1.45ms)
data.dtn.flood_test.test_meshtastic_contact_cancelled_during_backoff: PASS (766µs)
data.dtn.flood_test.test_meshtastic_contact_broadcast_success: PASS (586µs)
data.dtn.flood_test.test_meshtastic_ingress_hop_limit_reached: PASS (1.67ms)
data.dtn.flood_test.test_flood_generic_cddl_replication: PASS (1.64ms)
data.dtn.flood_test.test_flood_generic_cddl_wireless: PASS (3.48ms)
--------------------------------------------------------------------------------
Overall Total: 44/44 tests PASS
(14 foundations + 13 APRS/Trajectory + 17 Flooding/Quotas/Contention)
```

---

## 6. Comparative Synthesis: Which Protocol for Which Network?

| Feature | Epidemic Routing | Meshtastic Managed Flooding | Spray and Wait |
| :--- | :--- | :--- | :--- |
| **Maximum Number of Copies** | $N$ (All network nodes) | Unbounded (limited by radio TTL) | Strict bound $L$ fixed at emission |
| **Memory Consumption** | Catastrophic under load | Moderate (recent ID table) | Low and predictable |
| **Radio Spectrum Consumption** | Maximum (packet storms) | Optimized via SNR backoff | Low ($L-1$ intermediate transmissions) |
| **Ideal for** | Ultra-sparse networks without congestion | Local / community LoRa networks | Vehicle fleets, drones, emergency response networks |

In the next article (**Article 3**), we will explore the family of **probabilistic opportunistic protocols** with **PRoPHET ([RFC 6693](https://www.rfc-editor.org/rfc/rfc6693.html))**: dynamic calculation of encounter probabilities, aging, and transitivity.

---

👉 **Next article:** [Article 3 — Opportunistic Routing and Encounter History: PRoPHET (RFC 6693) under Open Policy Agent](./article-3-prophet.en.md)
