# Article 1 — Transposing APRS Digipeating (AX.25 WIDE n-N) to DTN (BPv7) with Open Policy Agent

> **Series:** *Transposing Mesh & Opportunistic Routing Algorithms to DTN (BPv7)*  
> **Previous article:** [Article 0 — Foundations of DTN Routing with Open Policy Agent](./article-0-intro.en.md)  
> **CDDL Specification:** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl)  
> **Policy Code:** [policies/aprs/](./policies/aprs/) ([ingress.rego](./policies/aprs/ingress.rego), [contact.rego](./policies/aprs/contact.rego), [helpers.rego](./policies/aprs/helpers.rego), [constants.rego](./policies/aprs/constants.rego), [aprs_test.rego](./policies/aprs/aprs_test.rego))

> ℹ️ **Editorial Transparency Note (EU AI Act Alignment):** This article was generated with AI assistance under the editorial direction and structuring of a human author, who assumes responsibility for its technical review, verification, and content (ongoing proofreading).

---

## 1. Introduction: The Legacy of APRS and the New-N Paradigm

Created by Bob Bruninga (WB4APR) in the early 1990s, **APRS (Automatic Packet Reporting System)** is one of the world's first large-scale amateur radio mesh networks. Designed to operate over shared VHF frequencies (typically 144.800 MHz in Europe) using unnumbered **AX.25 UI (*Unnumbered Information*)** frames, APRS relies on a simplified relaying mechanism known as **digipeating**.

In the AX.25 header, a sender specifies a list of intermediate repeaters. Under the modern **New-N (WIDE n-N)** paradigm:
1. A packet transmitted with trajectory `WIDE1-1, WIDE2-1` is first picked up by a fill-in digipeater.
2. This relay decrements the SSID `WIDE1-1` to `WIDE1*` (or substitutes its own callsign with the H bit set: `F4KXL-1*`) and rebroadcasts the frame.
3. A second high-altitude wide digipeater picks up the frame, decrements `WIDE2-1` to `WIDE2*`, and rebroadcasts.
4. Once all aliases are consumed (SSID = 0), no digipeater rebroadcasts the packet.
5. A duplicate suppression window (typically 30 seconds) prevents loops and echo storms between neighboring relays.

### Why Transpose This Mechanism to DTN?
Although brilliant in its simplicity, traditional AX.25 suffers from severe limitations:
- Total absence of native encryption and authentication (vulnerable to spoofing).
- Reliance on a synchronous radio medium (no delay-tolerant retention for extended periods).
- Fixed header format limited to 8 hops.

By transposing APRS digipeating into **Bundle Protocol v7 ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html))**, we benefit from end-to-end security via **BPSec ([RFC 9172](https://www.rfc-editor.org/rfc/rfc9172.html))**, native loop prevention through **Hop Count (Type 10)**, and persistent **Store-Carry-and-Forward** storage.

---

## 2. CBOR / CDDL Specification: The Mesh Extension Block

To reconcile APRS with future algorithms (Spray & Wait, PRoPHET, Reticulum, Meshtastic), we formalized a unified BPv7 extension block in [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl).

### 2.1. Past vs Future Duality: TREB and Trajectory Block
A key architectural point highlighted in our analysis:
- The **Traceroute Extension Block (TREB - `draft-koo-dtn-traceroute-eb`)** records the **past trajectory**: which nodes have already been traversed, at what time, and with what metrics.
- Our new mesh routing block carries the **future trajectory**: which strict nodes or generic aliases (`WIDE n-N`) must still relay the bundle.

### 2.2. CDDL Specification Excerpt for APRS

```cddl
; Modular and agnostic experimental BPv7 block (Type 200)
mesh-routing-data = {
    ? 1 => legacy-bridge-id: (bytes / uint), ; Optional external fingerprint (AX.25 gateway)
    ? 3 => trajectory-control,               ; Ordered future trajectory primitives
    ...
}

trajectory-control = {
    1 => path-elements: [* path-element],  ; Ordered list of future/past hops
    2 => active-hop-index: uint,           ; 0-based pointer to active hop
    ? 3 => allow-substitution: bool        ; Allows alias substitution by real identifier
}

path-element = strict-target / scoped-alias

; Strict waypoint to a specific node or callsign (e.g., "F4KXL-1")
strict-target = {
    1 => target-type: 1,                   ; 1 = Strict target
    2 => target-id: tstr,                  ; EID or Callsign
    3 => completed: bool                   ; True if already relayed (AX.25 H-bit)
}

; Waypoint with scoped generic alias (New-N paradigm: WIDE1-1, WIDE2-2, etc.)
scoped-alias = {
    1 => target-type: 2,                   ; 2 = Generic alias
    2 => scope-name: tstr,                 ; "WIDE1", "WIDE2", "RELAY", "LOCAL"
    3 => max-count: uint,                  ; Initial count N
    4 => remaining-count: uint,            ; Remaining count decremented at each relay
    5 => completed: bool,                  ; True when remaining-count == 0
    ? 6 => serviced-by: tstr               ; Real identifier of relaying station
}
```

### 2.3. Reconciliation with Hop Count Block (Type 10) and Bundle ID

Two major architectural trade-offs emerge from this transposition:

1. **Global Safeguard vs Role Semantics:**  
   For a composite APRS path like `WIDE1-1, WIDE2-2`, the maximum total hop count is $1 + 2 = 3$. When the bundle is emitted, the **Hop Count Block (Type 10)** is initialized with `hop_limit = 3`. At each relay (whether a `WIDE1`, a `WIDE2`, or a strict hop), the `hop_count` of the Type 10 block is incremented by 1. Even if a buggy relay fails to decrement its alias, the standard BPv7 block drops the bundle as soon as the limit is reached.
2. **Dupe Cache and Bundle ID:**  
   In analog AX.25, the lack of message identifiers forced digipeaters to construct an ephemeral hash $\text{hash}(\text{source}, \text{dest}, \text{info})$. In DTN, the canonical **Bundle ID** `(source_eid, time, seq)` natively and universally fulfills this role. No dedicated message identifier field is therefore required in the extension block for DTN nodes.

---

## 3. Decision Logic and OPA Policies (Rego)

APRS logic is declaratively implemented in [policies/aprs/](./policies/aprs/).

```
                 [ Bundle Ingress (AX.25 / LoRa) ]
                                |
                                v
               +---------------------------------+
               |    Dupe Cache (30s) checked?    |---(Yes)---> [ DROP ]
               +---------------------------------+
                                | (No)
                                v
               +---------------------------------+
               |    Is node a Digipeater?        |---(No)---> [ DROP ]
               +---------------------------------+
                                | (Yes)
                                v
               +---------------------------------+
               |   Examine active hop (index)    |
               +---------------------------------+
                 /                             \
     (Strict Hop / Callsign)         (Generic Alias WIDE n-N)
               /                                 \
   +-------------------------+       +-------------------------------+
   |   Matches my node?      |       |    Is alias supported?        |
   +-------------------------+       +-------------------------------+
      /                   \               /                     \
   (Yes)                 (No)          (Yes)                  (No)
     |                     |              |                      |
[ ACCEPT ]             [ SKIP ]    +---------------+         [ SKIP ]
(Advance index,                    | remaining > 1 |
 digipeated=true)                  +---------------+
                                      /         \
                                   (Yes)       (No, =1)
                                     |             |
                                [ ACCEPT ]     [ ACCEPT ]
                                (Decrement     (remaining=0,
                                 remaining,     digipeated=true,
                                 index stable)  advance index)
```

### 3.1. Ingress Policy ([ingress.rego](./policies/aprs/ingress.rego))

#### Rule 1: Immediate Deduplication (Dupe Suppression Cache)
Just like in analog APRS, a digipeater ignores a packet if it has already been processed recently:
```rego
decision := {
    "action": "DROP",
    "reason": "Duplicate packet detected in seen cache",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    helpers.is_duplicate(input.bundle, input.node.seen_cache)
}
```

#### Rule 2: Decrementing a `WIDEn-N` Alias (`remaining_hops > 1`)
Example: a packet arrives with `WIDE2-2`. Local node `F4KXL-1` accepts alias `WIDE2`:
- It decrements `remaining_hops` to `1`.
- It substitutes its callsign (`substituted_by: "F4KXL-1"`).
- **The pointer `active_hop_index` remains on this element**, as one `WIDE2-1` hop remains to be consumed by the next relay!
```rego
decision := {
    "action": "ACCEPT_DIGIPEAT",
    "reason": sprintf("Generic alias %v decremented to %v", [hop.alias_name, hop.remaining_hops - 1]),
    "mutations": [{
        "block_type": 200,
        "operation": "MUTATE_APRS_PAYLOAD",
        "active_hop_index": block.payload.active_hop_index, # Still on this hop
        "updated_hop_index": block.payload.active_hop_index,
        "updated_hop": object.union(hop, {
            "remaining_hops": hop.remaining_hops - 1,
            "substituted_by": input.node.callsign
        }),
        "cache_hash": block.payload.dupe_suppression_hash
    }]
} if {
    ...
    hop.hop_kind == constants.hop_kind_alias
    helpers.is_alias_supported(hop.alias_name, input.node.supported_aliases)
    hop.remaining_hops > 1
}
```

#### Rule 3: Final Consumption of an Alias (`remaining_hops == 1`)
Example: a packet arrives with `WIDE1-1` or `WIDE2-1`:
- `remaining_hops` drops to `0`.
- `digipeated` becomes `true`.
- **The pointer `active_hop_index` advances by 1** to move to the next hop in the trajectory.
```rego
decision := {
    "action": "ACCEPT_DIGIPEAT",
    "reason": sprintf("Generic alias %v fully consumed", [hop.alias_name]),
    "mutations": [{
        "block_type": 200,
        "operation": "MUTATE_APRS_PAYLOAD",
        "active_hop_index": block.payload.active_hop_index + 1, # Advances to next hop
        "updated_hop_index": block.payload.active_hop_index,
        "updated_hop": object.union(hop, {
            "remaining_hops": 0,
            "digipeated": true,
            "substituted_by": input.node.callsign
        }),
        "cache_hash": block.payload.dupe_suppression_hash
    }]
} if {
    ...
    hop.remaining_hops == 1
}
```

#### Rule 4: Strict Hop (Explicit Source Routing)
If the path element is a specific node (e.g., `F4KXL-1`):
- If callsign matches local node: hop is validated, marked `digipeated = true`, and index advances (`ACCEPT_DIGIPEAT`).
- If callsign is destined for another station: packet is skipped (`SKIP`).

---

## 4. Compliance with Dire Wolf Recommendations (WB2OSZ - *APRS-Digipeaters.pdf*)

In his reference document [*APRS Digipeaters* (John Langner, WB2OSZ)](https://github.com/wb2osz/direwolf-doc/blob/main/APRS-Digipeaters.pdf), Dire Wolf's author formalizes requirements for a modern, well-behaved digipeater facing old firmware inconsistencies (TNC-2, KPC-3+). Our DTN implementation strictly complies with these recommendations:

| Dire Wolf Rule (*APRS-Digipeaters.pdf*) | WB2OSZ Specification | DTN / OPA Implementation | Associated Test |
| :--- | :--- | :--- | :--- |
| **Section 6.1(b)** | *Is the source my station address? If so, return NO.* | Immediate detection via `helpers.is_own_packet`. Packet is immediately dropped (`DROP`) to prevent echo loops. | `test_aprs_direwolf_6_1b_suppress_own_packet` |
| **Section 6.2(a)** | *Suppress any duplicates (30 seconds cache on source, dest, info).* | Filtering via `helpers.is_duplicate` on deduplication hash (exposed in `node.seen_cache`). | `test_aprs_duplicate_suppression` |
| **Section 6.3(a) & 7** | *Adaptive insertion / replacement for $N \ge 2$.* | For `WIDEn-N` ($N \ge 2$), decrements `remaining_hops`, appends callsign in `substituted_by`, and maintains index on hop. | `test_aprs_generic_alias_decremented` |
| **Section 6.3(b) & 7** | *When $N = 1$, replace by callsign and mark as used (no $N=0$ dangling).* | Unlike old TNC bugs (KPC-3+ v8.2) leaving dangling `WIDE1*`, alias is marked `digipeated: true` and index advances to next hop. | `test_aprs_generic_alias_fully_consumed` |
| **Section 6.3(c)** | *If $N = 0$, hop count is used up: do NOT repeat.* | Strict rejection if packet arrives with alias where `remaining_hops <= 0` not marked digipeated. | `test_aprs_direwolf_6_3c_drop_exhausted_alias` |
| **Section 10** | *Trapping larger values of N (`^WIDE[3-7]-[1-7]$`).* | Radio saturation protection: aliases configured in `trapped_aliases` are clamped and relayed once and only once. | `test_aprs_direwolf_section_10_trapping_excessive_alias` |

---

## 5. OPA Unit Test Validation (27/27 PASS)

The dedicated unit test suite ([aprs_test.rego](./policies/aprs/aprs_test.rego)) validates 13 representative scenarios:

```bash
opa test ./policies -v
```

```text
./policies/aprs/aprs_test.rego:
data.dtn.aprs_test.test_aprs_local_delivery: PASS (906µs)
data.dtn.aprs_test.test_aprs_duplicate_suppression: PASS (2.08ms)
data.dtn.aprs_test.test_aprs_strict_hop_matched: PASS (4.15ms)
data.dtn.aprs_test.test_aprs_strict_hop_not_for_me: PASS (4.08ms)
data.dtn.aprs_test.test_aprs_generic_alias_decremented: PASS (7.42ms)
data.dtn.aprs_test.test_aprs_generic_alias_fully_consumed: PASS (3.80ms)
data.dtn.aprs_test.test_aprs_unsupported_alias: PASS (4.40ms)
data.dtn.aprs_test.test_aprs_contact_broadcast: PASS (389µs)
data.dtn.aprs_test.test_aprs_contact_unicast_match: PASS (572µs)
data.dtn.aprs_test.test_aprs_direwolf_6_1b_suppress_own_packet: PASS (1.26ms)
data.dtn.aprs_test.test_aprs_direwolf_6_3c_drop_exhausted_alias: PASS (3.18ms)
data.dtn.aprs_test.test_aprs_direwolf_section_10_trapping_excessive_alias: PASS (4.54ms)
data.dtn.aprs_test.test_aprs_generic_cddl_trajectory: PASS (1.85ms)
--------------------------------------------------------------------------------
Overall total: 27/27 tests PASS (14 base + 13 APRS)
```

---

## 6. What This Approach Brings to Amateur Radio & Mesh

1. **Total flexibility of relay rules:**  
   No need to recompile TNC firmware or an AX.25 daemon to adjust behavior. By simply modifying the Rego policy, an operator can:
   - Disable `WIDE2` support at night or under low battery voltage.
   - Enable or disable trapping based on local radio traffic density.
   - Restrict digipeating solely to packets emitted by emergency (SAR) or weather beacons.
2. **Secure encapsulation:**  
   APRS packets are no longer plaintext AX.25 frames vulnerable to spoofing. They benefit from BPSec signatures (BIB) and can transit transparently over 1200 baud VHF, LoRa, or IP/AREDN links alike.
3. **Past/Future Synergy:**  
   Coupling our future trajectory block with the standard **Traceroute Extension Block (TREB)** enables complete visibility of a packet's path without cluttering routing.

In the next article (**Article 2**), we will transpose the **Spray and Wait** protocol: replication quota management ($L$), binary distribution ($L/2$), and dynamic transition to the *Wait* phase.

---

👉 **Next article:** [Article 2 — Taming Flooding in DTN: From Epidemic to Spray and Wait and Meshtastic Managed Flooding](./article-2-flood.en.md)
