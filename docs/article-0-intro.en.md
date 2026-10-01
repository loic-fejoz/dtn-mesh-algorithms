# Article 0 — Foundations of DTN Routing with Open Policy Agent: Lifecycle, Hop Limit, and Expiration

> **Series:** *Transposing Mesh & Opportunistic Routing Algorithms to DTN (BPv7)*  
> **Author:** DTN Mesh Research & Engineering  
> **Associated Code:** [policies/](./policies) ([ingress.rego](./policies/ingress.rego), [storage.rego](./policies/storage.rego), [contact.rego](./policies/contact.rego), [helpers.rego](./policies/helpers.rego), [dtn_constants.rego](./policies/dtn_constants.rego))

> ℹ️ **Editorial Transparency Note (EU AI Act Alignment):** This article was generated with AI assistance under the editorial direction and structuring of a human author, who assumes responsibility for its technical review, verification, and content (ongoing proofreading).

---

## 1. Introduction: Why Drive a DTN Router with OPA?

The **Bundle Protocol version 7 ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html))** is designed to operate over heterogeneous, intermittent, and high-latency networks (deep-space links, tactical mesh networks, LoRa sensors, AX.25 amateur radio links). Unlike the traditional IP stack where routing is delegated to static forwarding tables or real-time dynamic protocols (BGP, OSPF), DTN relies on the **Store-Carry-and-Forward** paradigm:

1. A node receives a bundle.
2. It validates and stores it in its persistent storage (*Bundle Store*).
3. It waits for a contact opportunity (sometimes several hours or days).
4. It selects eligible bundles and forwards them to a peer via a Convergence Layer Adapter (CLA).

In the majority of historical implementations (ION, IBR-DTN, uD3TN), routing rules (Epidemic, PRoPHET, CGR) are hardcoded in C/C++ or Python, tightly coupled with the routing daemon's event loop.

**Our Architectural Thesis:**  
By delegating decision-making to a declarative policy engine like **Open Policy Agent (OPA)** via the **Rego** language, we strictly separate:
- **Data Plane:** CBOR reception, BPSec cryptographic validation ([RFC 9172](https://www.rfc-editor.org/rfc/rfc9172.html)), disk persistence, and CLA transmission.
- **Control/Decision Plane:** Enforcement of retention rules, replication quota computation, contact filtering, loop detection, and dropping invalid bundles.

Before tackling complex algorithms like Spray and Wait, PRoPHET, or APRS digipeating, this first article establishes the **elementary, non-negotiable foundations** of any DTN node: **dropping bundles whose hop count limit is exceeded and those whose lifetime has expired.**

---

## 2. Fundamental RFC 9171 Rules

### 2.1. DTN Epoch vs Unix Epoch
A frequent source of bugs in DTN lies in time management. The standard Bundle Protocol epoch (DTN Time) is set to **January 1, 2000 at 00:00:00 UTC**, rather than January 1, 1970 (Unix Epoch). The exact offset is **946,684,800 seconds** (or `946,684,800,000 ms`).

### 2.2. Lifetime Expiration: The Pitfall of Real-Time-Clock-Less (RTC-less) Nodes
RFC 9171 handles two timestamping scenarios:
1. **Node with synchronized clock (`creation_timestamp.time > 0`):**  
   Expiration occurs as soon as:  
   $$\text{CurrentDTNTime} \ge \text{creation\_timestamp.time} + \text{lifetime}$$
2. **Node without synchronized clock (`creation_timestamp.time == 0`):**  
   Very common on IoT/LoRa nodes or microcontrollers rebooted without GPS or NTP. In this case, RFC 9171 **mandates** the presence of the **Bundle Age Block (Type 7)**. The relative bundle age $\text{bundle\_age}$ is incremented in milliseconds along the transit and storage path. Expiration occurs as soon as:  
   $$\text{bundle\_age} \ge \text{lifetime}$$

### 2.3. Hop Count Block (Type 10) and Storm Prevention
The **Hop Count Block (Type 10)** contains two unsigned integers: `hop_limit` and `hop_count`.
Section 4.3.3 of RFC 9171 specifies two critical moments:
- **At reception (*Ingress*):** The node **MUST** increment `hop_count` by 1. If $\text{hop\_count} \ge \text{hop\_limit}$, the bundle **MUST** be destroyed (unless it is destined for the local node).
- **Before transmission (*Forwarding*):** If $\text{hop\_count} \ge \text{hop\_limit}$, the bundle **MUST** be destroyed and **MUST NOT** be forwarded.

### 2.4. Bundle Deletion Status Reports
When the `deletion_report` flag (bit 14 of the bundle processing control flags) is set by the sender, the DTN engine must generate a status report administrative bundle with the standardized reason code:
- Reason `1`: `Lifetime expired`
- Reason `9`: `Hop limit exceeded`

### 2.5. Canonical Bundle Identity: Uselessness of Ad-Hoc `packet-id`s
A major architectural difference between DTN and ad-hoc or amateur radio mesh networks (APRS, Meshtastic) lies in how message uniqueness is managed:
- **In AX.25 (APRS):** UI frames contain no link-layer message identifier. Digipeaters had to invent an ad-hoc hash: $\text{hash}(\text{source}, \text{dest}, \text{info})$ to detect duplicates.
- **In Meshtastic:** The LoRa header inserts a 32-bit pseudo-random integer (`packet_id`).
- **In DTN (BPv7 RFC 9171 Section 4.2.2):** Every bundle **natively** possesses a universal, canonical, globally unique identity:
  $$\text{BundleID} = (\text{source\_eid}, \text{creation\_timestamp.time}, \text{creation\_timestamp.sequence\_number})$$

Even on clockless nodes (`time == 0`), the monotonic sequence number guarantees this uniqueness per sending station. In our Rego policies, deduplication and summary vectors rely directly on this tuple ([helpers.rego](./policies/helpers.rego)) via `helpers.get_bundle_id(bundle)`. No additional message identifier field needs to be added into an extension block.

Likewise, the **Hop Count Block (Type 10)** stands as the universal safeguard: every mesh algorithm (whether Meshtastic or APRS WIDE n-N) reconciles its hop count with this standard block.

### 2.6. Denial of Service (DoS) Protection and Malicious Nodes: `blacklist_sources`
In open mesh and opportunistic networks (amateur radio VHF/AX.25, LoRa sensors, emergency tactical networks), any station within radio range can inject frames into the ether. In the event of hardware failure (a looping node saturating the frequency) or malicious storage exhaustion attacks, a DTN router must be capable of blocking the sender without delay.

Rather than recompiling or restarting the DTN daemon, we incorporate the `blacklist_sources: [* tstr]` field into the node context ([mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl)). Upon bundle arrival, the Ingress policy checks whether the source EID appears in this list:
- The bundle is immediately rejected (`DROP`) prior to any memory allocation or disk persistence.
- **Crucial security rule:** The node **generates no deletion status report** (`generate_status_report := false`). Systematically replying to a malicious sender would create traffic amplification risks and further saturate the shared radio channel.

---

## 3. Declarative Policy Architecture: 3-Stage Breakdown

Having a single monolithic policy is inefficient and conceptually flawed. In a DTN system, forwarding decisions take place at three distinct moments in the bundle lifecycle:

```
                  +-----------------------------------+
                  |        Bundle Arrives (CLA)       |
                  +-----------------------------------+
                                    |
                                    v
                     [ 1. Ingress Policy (on_rx) ]
                                    |
                        +------------+------------+
                        |                         |
                    [ACCEPT]                    [DROP]
                        |                         |
                        v                         v
             +--------------------+       (Optional: Status Report)
             |    Bundle Store    |
             +--------------------+
                |              |
                | (periodic)   | (CLA opportunity)
                v              v
       [ 2. Storage Policy ]  [ 3. Contact Policy ]
          (Audit / GC)          (Forwarding)
                |                      |
             [DROP / RETAIN]      [FORWARD / SKIP / DROP]
```

### Stage 1: Ingress Policy (`dtn.ingress`) — Immediate Reception
* **When?** As soon as a bundle is extracted from a CLA link (LoRa, AX.25, TCPCL).
* **Inputs:** `bundle`, `node.local_eid`, `node.blacklist_sources`, `ingress.peer_eid`, `current_dtn_time_ms`.
* **Role:**
  0. If `source` is listed in `blacklist_sources`: Immediate `DROP` without status report (anti-spam / DoS).
  1. If `destination == local_eid`: Priority local delivery (`DELIVER_LOCAL`).
  2. If `is_lifetime_expired`: `DROP` (code 1).
  3. If `will_exceed_hop_limit`: `DROP` (code 9).
  4. Otherwise: `ACCEPT` with mandatory CBOR mutation: `hop_count = hop_count + 1`.

### Stage 2: Storage Audit Policy (`dtn.storage`) — Periodic Garbage Collector
* **When?** Executed periodically by a timer (e.g., every 10 seconds or 1 minute) or during buffer memory saturation alerts.
* **Inputs:** `bundle`, `current_dtn_time_ms`, `elapsed_since_last_audit_ms`.
* **Role:**
  1. Check if lifetime expired during buffer retention. If so, `DROP` (code 1).
  2. If the bundle is clockless (`time == 0`), order mutation of the **Bundle Age Block (Type 7)** to add elapsed storage time.

### Stage 3: Contact Policy (`dtn.contact`) — CLA Link Opportunity
* **When?** When a link with a neighbor node is detected or a CLA link is established.
* **Inputs:** `bundle`, `node`, `contact.peer_eid`, `contact.cla_type`, `current_dtn_time_ms`.
* **Role:**
  1. Re-verify time validity and hop limit prior to forwarding.
  2. Verify immediate loop avoidance (*Split Horizon*): do not echo the bundle back to the proximate sender indicated in the **Previous Node Insertion Block (Type 6)** (`SKIP`).
  3. Decide forwarding: `FORWARD` if the contact is the final destination or a valid opportunistic relay.

---

## 4. Rego Specification and Implementation

All rules are implemented and validated in the [`policies/`](./policies) directory.

### 4.1. Constants and Helpers ([dtn_constants.rego](./policies/dtn_constants.rego) & [helpers.rego](./policies/helpers.rego))

```rego
package dtn.helpers

import future.keywords.if
import future.keywords.in
import data.dtn.constants

# Unified detection of lifetime expiration
is_lifetime_expired(bundle, current_dtn_time_ms) if {
    bundle.primary.creation_timestamp.time > 0
    expiration_time := bundle.primary.creation_timestamp.time + bundle.primary.lifetime
    current_dtn_time_ms >= expiration_time
}

is_lifetime_expired(bundle, _) if {
    bundle.primary.creation_timestamp.time == 0
    age_block := get_extension_block(bundle.extension_blocks, constants.block_type_bundle_age)
    age_block.bundle_age_ms >= bundle.primary.lifetime
}

# Hop limit exceeded detection
will_exceed_hop_limit(bundle) if {
    hcb := get_hop_count_block(bundle)
    (hcb.hop_count + 1) >= hcb.hop_limit
}
```

### 4.2. Ingress Policy ([ingress.rego](./policies/ingress.rego))

```rego
package dtn.ingress

import data.dtn.constants
import data.dtn.helpers

# 0. Immediate rejection if source is blacklisted (Anti-Spam / DoS)
decision := {
    "action": "DROP",
    "reason_code": constants.reason_depleted_storage,
    "reason": "Source EID is blacklisted on this node",
    "generate_status_report": false,
    "mutations": []
} if {
    helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
}

# 1. Local delivery
decision := {
    "action": "DELIVER_LOCAL",
    "reason": "Destination matches local node",
    "generate_status_report": false,
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination == input.node.local_eid
}

# 2. Lifetime expiration upon arrival
decision := {
    "action": "DROP",
    "reason_code": constants.reason_lifetime_expired,
    "reason": "Bundle lifetime has expired upon arrival",
    "generate_status_report": helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination != input.node.local_eid
    helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 3. Hop limit exceeded
decision := {
    "action": "DROP",
    "reason_code": constants.reason_hop_limit_exceeded,
    "reason": "Hop limit exceeded after ingress hop increment",
    "generate_status_report": helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    helpers.will_exceed_hop_limit(input.bundle)
}

# 4. Acceptance and hop count increment
decision := {
    "action": "ACCEPT",
    "reason": "Bundle accepted for forwarding / storage",
    "generate_status_report": false,
    "mutations": [{
        "block_type": constants.block_type_hop_count,
        "operation": "SET_FIELD",
        "field": "hop_count",
        "value": hop_block.hop_count + 1
    }]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.will_exceed_hop_limit(input.bundle)
    hop_block := helpers.get_hop_count_block(input.bundle)
}
```

### 4.3. Storage Retention Policy ([storage.rego](./policies/storage.rego))

```rego
package dtn.storage

import data.dtn.constants
import data.dtn.helpers

decision := {
    "action": "DROP",
    "reason_code": constants.reason_lifetime_expired,
    "reason": "Bundle lifetime expired during storage retention",
    "generate_status_report": helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}
```

### 4.4. CLA Contact Policy ([contact.rego](./policies/contact.rego))

```rego
package dtn.contact

import data.dtn.constants
import data.dtn.helpers

# Loop avoidance: do not forward back to proximate sender
decision := {
    "action": "SKIP",
    "reason": "Peer is the previous sender (split-horizon / loop avoidance)",
    "generate_status_report": false,
    "mutations": []
} if {
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_hop_limit_reached(input.bundle)
    pib := helpers.get_extension_block(input.bundle.extension_blocks, constants.block_type_previous_node)
    pib.previous_node == input.contact.peer_eid
}
```

---

## 5. OPA Unit Test Validation

The unit test suite validates all execution paths and runs directly via the `opa` CLI:

```bash
opa test ./policies -v
```

**Results:**
```text
./policies/contact_test.rego:
data.dtn.contact_test.test_contact_drop_expired: PASS (2.05ms)
data.dtn.contact_test.test_contact_drop_hop_limit_reached: PASS (964µs)
data.dtn.contact_test.test_contact_skip_previous_node: PASS (1.10ms)
data.dtn.contact_test.test_contact_forward_direct_destination: PASS (1.57ms)
data.dtn.contact_test.test_contact_forward_opportunistic_relay: PASS (1.33ms)

./policies/ingress_test.rego:
data.dtn.ingress_test.test_ingress_local_delivery: PASS (504µs)
data.dtn.ingress_test.test_ingress_drop_lifetime_expired_timed: PASS (1.08ms)
data.dtn.ingress_test.test_ingress_drop_lifetime_expired_untimed: PASS (1.13ms)
data.dtn.ingress_test.test_ingress_drop_hop_limit_reached: PASS (1.55ms)
data.dtn.ingress_test.test_ingress_accept_and_mutate_hop_count: PASS (1.35ms)
data.dtn.ingress_test.test_ingress_drop_blacklisted_source: PASS (698µs)

./policies/storage_test.rego:
data.dtn.storage_test.test_storage_drop_lifetime_expired_timed: PASS (403µs)
data.dtn.storage_test.test_storage_drop_lifetime_expired_untimed: PASS (706µs)
data.dtn.storage_test.test_storage_retain_and_update_age: PASS (1.19ms)
--------------------------------------------------------------------------------
PASS: 14/14 (base policies)
```

---

## 6. Questions and Perspectives for Subsequent Articles

This functional foundation opens key issues to tackle when transposing more advanced mesh algorithms:

1. **Congestion management and buffer eviction:**  
   If local storage is full (`storage_used >= storage_capacity`), which bundle to drop? A blind FIFO policy? The bundle with the smallest remaining lifetime? Or an eviction policy based on global utility (like MaxProp)?
2. **Status Reports Feedback:**  
   If OPA instructs `generate_status_report = true`, the DTN daemon must generate an administrative bundle to the source. How to ensure these status reports do not themselves cause a flooding storm over a bandwidth-constrained radio network?
3. **Convergence Layer Adapter (CLA) constraints:**  
   Certain links (e.g., LoRa with 1% duty cycle, or AX.25 at 1200 baud) cannot accept large bundles. The `input.contact` object will need to expose MTU and estimated bitrate to filter oversized bundles.
4. **Complex CBOR mutations:**  
   In this article, the sole mutation was incrementing `hop_count`. For APRS, the mutation will consist of consuming an alias `WIDE1-1 -> WIDE1*` and appending the relay callsign into a trace block. For Spray and Wait, it will involve dividing a replication quota $L \leftarrow \lfloor L/2 \rfloor$.

In the next article (**Article 1**), we will directly tackle transposing **APRS digipeating (AX.25)**: formalizing the new future path extension block (*Path Trajectory Block*) and authoring the associated Rego rules.

---

👉 **Next article:** [Article 1 — Transposing APRS Digipeating (AX.25 WIDE n-N) to DTN (BPv7)](./article-1-aprs.en.md)
