# Article 5 — Hybrid Routing, Distance-Vector, and Cryptographic Addressing: Reticulum (RNS) Transposed to DTN

> **CDDL Specifications:** [mesh-algo-extension-block.cddl](./mesh-algo-extension-block.cddl), [prophet.cddl](./prophet.cddl) & [reticulum.cddl](./reticulum.cddl)  
> **Policy Code:** [policies/reticulum/](./policies/reticulum/) ([ingress.rego](./policies/reticulum/ingress.rego), [contact.rego](./policies/reticulum/contact.rego), [storage.rego](./policies/reticulum/storage.rego), [helpers.rego](./policies/reticulum/helpers.rego), [constants.rego](./policies/reticulum/constants.rego), [reticulum_test.rego](./policies/reticulum/reticulum_test.rego))

> ℹ️ **Editorial Transparency Note (EU AI Act Alignment):** This article was generated with AI assistance under the editorial direction and structuring of a human author, who assumes responsibility for its technical review, verification, and content (ongoing proofreading).

---

## 1. The Zero-IP Imperative and Self-Sovereign Identity

So far, our exploration of mesh and delay-tolerant networks has covered:
1. Source routing and routing alias consumption under radio constraints ([APRS AX.25](./article-1-aprs.en.md)).
2. Regulated flooding via strict quotas or physical channel delay timers ([Spray and Wait & Meshtastic](./article-2-flood.en.md)).
3. Opportunistic routing guided by statistical learning of human contacts ([PRoPHET RFC 6693](./article-3-prophet.en.md)).
4. Transmission scheduling and buffer eviction based on information theory ([MaxProp](./article-4-maxprop.en.md)).

However, all of these protocols rely either on static administrative identifiers (amateur radio callsigns in APRS, MAC addresses/node numbers in Meshtastic, textual URIs in PRoPHET) or on global flooding of every message.

What happens when we want to build a **fully decentralized network, with no central coordination, no IP addresses, no DNS servers, while guaranteeing end-to-end encryption and accurate unicast routing on a planetary scale**?

That is precisely the goal of the **Reticulum Network Stack (RNS)**, designed by Mark Qvist. Reticulum stems from a radical observation: the traditional TCP/IP stack imposes address hierarchies (subnets, BGP prefixes, default gateways) ill-suited for ad-hoc networks, extremely low-bitrate radio links (LoRa, HF, VHF), and hostile environments where anonymity and cryptographic sovereignty are paramount.

---

## 2. The Architectural Pillars of Reticulum

```
+-----------------------------------------------------------------------------+
|                           RETICULUM NETWORK STACK                           |
+-----------------------------------------------------------------------------+
|  1. Self-Sovereign Cryptographic Addressing                                 |
|     -> SHA-256 hash truncated to 16 bytes (128 bits) of the public key      |
+-----------------------------------------------------------------------------+
|  2. Path Discovery via Signed Announcements (Announces)                     |
|     -> Public Key + Random Salt + Hop Count + Ed25519 Signature             |
+-----------------------------------------------------------------------------+
|  3. Next-Hop Distance-Vector Routing Table                                  |
|     -> Shortest announcement updates the designated next-hop relay          |
+-----------------------------------------------------------------------------+
|  4. Cryptographic Proofs of Delivery (Proofs)                                |
|     -> Receipt signature mathematically proving bundle reception            |
+-----------------------------------------------------------------------------+
```

### 2.1. Cryptographic Hash Addressing (16 bytes / 128 bits)
In Reticulum, a destination is neither a domain name nor an IP address. It is the **SHA-256 hash truncated to the first 16 bytes (128 bits)** of the destination's public key (or a public key + application aspect pair).
- **Self-authentication:** Any node can generate an asymmetric key pair (Curve25519 for ECDH, Ed25519 for signature) locally, without requesting authorization from a Certificate Authority.
- **Transposition to DTN (BPv7):** The destination EID takes the natural form:
  $$\text{dtn://rns/} \langle 16\text{-byte-hex-hash} \rangle /$$
  Example: `dtn://rns/a1b2c3d4e5f60718293a4b5c6d7e8f90/`. The EID integrates directly into the standard Primary Block of [RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html).

### 2.2. Path Discovery: Signed Announcements (*Announces*)
For a node to receive unicast messages, it broadcasts an **Announce** across the network.
Each announcement carries:
1. The destination hash (16 bytes).
2. The destination's full public key (32 bytes).
3. A 10-byte random salt (to prevent replay attacks).
4. A hop count initialized to `0`.
5. An Ed25519 cryptographic signature (64 bytes) covering the whole structure.
6. Optionally, encrypted application data or an ephemeral ratchet key for Forward Secrecy.

As the announcement propagates hop-by-hop:
- Each intermediate node relaying it increments the hop count.
- It records in its **local routing table**:
  $$\text{Destination Hash} \implies (\text{Next Hop} = \text{Immediate Sender Peer}, \text{Distance} = \text{Hops} + 1, \text{Expiration} = \text{Now} + \text{TTL})$$
- If a subsequent announcement reaches the node with a hop count greater than or equal to the recorded metric, it is ignored. If it offers a **strictly shorter** path, the route is updated.

### 2.3. Next-Hop Unicast Forwarding
Once routing tables are populated by announcements:
- Data bundles destined for that address are **no longer flooded**.
- The node checks its routing table, identifies the immediate neighbor (`next_hop_eid`), and forwards the packet exclusively to that peer.
- Each successive hop repeats this operation until reaching the final destination.

### 2.4. Reactive Discovery: Path Requests
If a node needs to send a bundle to a destination for which it has no cached announcement, it emits a `Path Request` control message.
Any intermediate node holding a valid path to that destination can reply with a `Path Response` containing the last valid signed announcement as proof.

---

## 3. The Masterstroke: Zero Specific Wire Blocks for Data in DTN

One of the most elegant findings of our architectural modeling concerns the wire format: **just like Meshtastic in [Article 2](./article-2-flood.en.md), Reticulum requires no proprietary extension block on the wire to forward data bundles in DTN.**

Let's examine why:

| Reticulum Requirement | Native RNS Implementation | Standard BPv7 Equivalent ([RFC 9171](https://www.rfc-editor.org/rfc/rfc9171.html)) | Required Block on the Wire? |
| :--- | :--- | :--- | :--- |
| **Recipient Identifier** | 16-byte truncated hash in packet header | Destination EID in Primary Block (`dtn://rns/<hash>/`) | **RFC 9171 Standard** (Primary Block) |
| **Loop Prevention** | Decremented hop limit counter | **Hop Count Block (Type 10)** (`hop_limit`, `hop_count`) | **RFC 9171 Standard** (Type 10) |
| **Deduplication** | Packet hash | **Canonical Bundle ID** `(source, time, sequence)` | **RFC 9171 Standard** (Section 4.2.2) |
| **Immediate Resend Avoidance** | Interface filtering | **Previous Node Insertion Block (Type 6)** | **RFC 9171 Standard** (Type 6) |
| **Next-Hop Routing Table** | Node's RAM table | Injected into OPA context (`input.node.routing_table`) | **Zero wire bytes** (OPA Local) |

Reticulum data packets therefore enjoy full interoperability with any standard DTN router adhering to RFC 9171.

---

## 4. Signaling Message Specification: `reticulum.cddl`

While data packets travel as standard bundles, inter-node signaling (Announces, Requests, and Proofs) requires a formalized exchange format.

In our architecture, these messages are encapsulated within the **payload of an administrative bundle** (e.g., addressed to `dtn://rns/announce` or to the remote peer via the CLA).

The file **[reticulum.cddl](./reticulum.cddl)** specifies these structures in CBOR:

```cddl
; Reticulum control message carried in the payload of an administrative bundle
reticulum-control-bundle = {
    1 => message-type: reticulum-message-type,
    2 => destination-hash: bytes .size 16,  ; SHA-256 hash truncated to 16 bytes
    3 => timestamp-ms: uint,                ; DTN creation clock
    4 => payload: reticulum-payload         ; Payload according to type
}

reticulum-message-type = &(
    msg-announce: 1,      ; Destination announcement and path discovery
    msg-path-request: 2,  ; Explicit path request to a destination
    msg-path-response: 3, ; Path response (path known by third party)
    msg-proof: 4          ; Receipt proof / cryptographic acknowledgement
)

; Structure of a signed Announce
announce-payload = {
    1 => public-key: bytes .size 32,        ; Ed25519 or Curve25519 public key
    2 => announce-hops: uint,               ; Announce hop counter (0 at origin)
    3 => random-salt: bytes .size 10,       ; Random salt (replay protection)
    4 => signature: bytes .size 64,         ; Ed25519 signature by destination key
    ? 5 => app-data: bytes,                 ; Encrypted or plain application metadata
    ? 6 => ratchet: bytes .size 32          ; Ephemeral key (Forward Secrecy)
}

; Cryptographic receipt proof (Proof)
proof-payload = {
    1 => bundle-id-hash: bytes .size 32,    ; Hash of the acknowledged bundle ID
    2 => signature: bytes .size 64          ; Signature by recipient's private key
}
```

---

## 5. Store-Carry-and-Forward: DTN's Revenge on Native Reticulum

In original Reticulum software (on microcontrollers or Raspberry Pi):
- If a node attempts to send a packet to a destination for which it holds **no routing table entry**, it triggers a *Path Request*.
- However, if no answer returns within a short timeout or if the immediate physical link is down, the packet is simply **dropped**, as Reticulum was not originally built as a long-term custody storage system.

This is where hybridization with **Bundle Protocol v7** demonstrates its operational superiority:

```
             Reticulum Data Flow in Disrupted Environments
             =============================================

       Bundle Emission towards dtn://rns/<hash>/
                          |
                          v
               Route known in table?
             /                       \
         [ YES ]                   [ NO ]
            |                         |
      Forward Next-Hop          Active DTN Custody (Store-Carry-and-Forward)
   (Unicast Forwarding)               |
                                Bundle retained in local buffer
                                      +
                                Optional Path Request trigger
                                      |
                                Later contact with an Announce carrier?
                                      |
                                [ Announce Received ]
                                      |
                                Routing table updated
                                      |
                                Deferred forward to new Next-Hop!
```

Thanks to DTN primitives, **no packet is lost during network partitioning**. The bundle waits in buffer (`action: "SKIP"` during irrelevant contacts, `action: "RETAIN_AND_REQUEST_PATH"` during storage audits), until physical contact brings the expected announcement.

---

## 6. Declarative Modeling under Open Policy Agent (OPA)

The directory **[policies/reticulum/](./policies/reticulum/)** implements all decision rules governing a Reticulum/DTN router's behavior.

### 6.1. Ingress: Announcement Ingestion and Table Updates ([ingress.rego](./policies/reticulum/ingress.rego))

At entry, policy logic distinguishes data packets from path announcements:

```rego
# Ingress Rule 6: Reticulum Announcement with shorter path discovery
decision := {
    "action": "ACCEPT_ANNOUNCE",
    "reason": sprintf("Reticulum announce accepted: discovered next-hop path to %v via %v (%v hops)", [
        announced_dest,
        peer_eid,
        hops + 1
    ]),
    "mutations": [
        {
            "operation": "UPDATE_ROUTING_TABLE",
            "destination_hash": announced_dest,
            "next_hop": peer_eid,
            "hops": hops + 1,
            "expires_at_ms": input.current_dtn_time_ms + constants.default_path_ttl_ms
        },
        {
            "block_type": base_constants.block_type_hop_count,
            "operation": "SET_FIELD",
            "field": "hop_count",
            "value": hops + 1
        }
    ]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    helpers.is_announce(input.bundle)
    announced_dest := input.bundle.primary.source
    peer_eid := object.get(input.ingress, "peer_eid", announced_dest)
    hcb := base_helpers.get_hop_count_block(input.bundle)
    hops := hcb.hop_count
    existing := helpers.get_route_entry(announced_dest, object.get(input.node, "routing_table", {}))
    helpers.should_update_path(existing, hops + 1, input.current_dtn_time_ms)
}
```

The helper function [helpers.should_update_path](./policies/reticulum/helpers.rego#L60-L73) formalizes distance-vector criteria:
1. No path was previously known for this destination.
2. The stored path has expired (`current_time > expires_at_ms`).
3. The incoming announcement offers a strictly shorter path (`new_hops < existing.hops`).

### 6.2. Contact: Unicast Forwarding to Designated Next-Hop ([contact.rego](./policies/reticulum/contact.rego))

When a transmission opportunity arises with a peer:
- If it is an announcement and the link is broadcast: re-broadcast (`FORWARD_BROADCAST`).
- If it is a data bundle and the connected peer is the recorded next-hop: immediate transmission (`FORWARD_NEXT_HOP`).
- If the connected peer is not the next-hop, or if the route is unknown: retain in storage (`SKIP`).

```rego
# Contact Rule 5: Forwarding to designated Next-Hop
decision := {
    "action": "FORWARD_NEXT_HOP",
    "reason": sprintf("Routing table match: forwarding to next-hop %v (%v hops to destination)", [
        route.next_hop_eid,
        route.hops
    ]),
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_announce(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    route != null
    helpers.is_route_valid(route, input.current_dtn_time_ms)
    input.contact.peer_eid == route.next_hop_eid
}
```

### 6.3. Storage: Triggering Path Requests in Background ([storage.rego](./policies/reticulum/storage.rego))

During periodic buffer sweeps:
- Orphan bundles (without a valid table route) trigger a `TRIGGER_PATH_REQUEST` mutation to trigger reactive discovery if allowed by the node.

```rego
decision := {
    "action": "RETAIN_AND_REQUEST_PATH",
    "reason": "Bundle destination route unknown or expired: trigger Reticulum path discovery",
    "mutations": [{
        "operation": "TRIGGER_PATH_REQUEST",
        "destination_hash": input.bundle.primary.destination
    }]
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_announce(input.bundle)
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    not is_valid_route(route, input.current_dtn_time_ms)
    object.get(input.node, "enable_path_requests", false) == true
}
```

---

## 7. Validation through OPA Unit Tests (92/92 PASS)

The implementation was validated by 16 comprehensive unit tests in [reticulum_test.rego](./policies/reticulum/reticulum_test.rego), bringing the test suite total to **92 passed tests with a 100% success rate**.

```bash
opa test ./policies -v
```

```text
policies/aprs/aprs_test.rego:
  13 tests passed (digipeating AX.25, Dire Wolf rules 6.1b, 6.3c, trapping §10)
policies/contact_test.rego:
  5 tests passed (contact CLA foundations, split-horizon, lifetime)
policies/flood/flood_test.rego:
  17 tests passed (binary/source Spray & Wait, Meshtastic SNR backoff and contention)
policies/ingress_test.rego:
  6 tests passed (ingress foundations, Hop Count Type 10, source blacklisting)
policies/maxprop/maxprop_test.rego:
  16 tests passed (logarithmic cost, smooth hop penalty, 2-hop gossip, cleared list)
policies/prophet/prophet_test.rego:
  16 tests passed (mathematical equations, RIB handshake, selective eviction)
policies/reticulum/reticulum_test.rego:
  data.dtn.reticulum_test.test_reticulum_ingress_local_delivery_by_eid: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_local_delivery_by_hash: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_blacklisted_source: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_expired: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_hop_limit_reached: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_announce_new_route: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_announce_shorter_path: PASS
  data.dtn.reticulum_test.test_reticulum_ingress_announce_longer_path_ignored: PASS
  data.dtn.reticulum_test.test_reticulum_contact_direct_destination: PASS
  data.dtn.reticulum_test.test_reticulum_contact_announce_broadcast: PASS
  data.dtn.reticulum_test.test_reticulum_contact_forward_matching_next_hop: PASS
  data.dtn.reticulum_test.test_reticulum_contact_skip_non_next_hop_peer: PASS
  data.dtn.reticulum_test.test_reticulum_contact_skip_unknown_destination: PASS
  data.dtn.reticulum_test.test_reticulum_contact_skip_expired_route: PASS
  data.dtn.reticulum_test.test_reticulum_storage_drop_expired: PASS
  data.dtn.reticulum_test.test_reticulum_storage_trigger_path_request: PASS
policies/storage_test.rego:
  3 tests passed (Bundle Age Block Type 7 handling)
--------------------------------------------------------------------------------
PASS: 92/92
```

---

## 8. Grand Comparative Synthesis of the 4 Algorithms

Here is the cross-cutting comparison of all protocols studied and implemented throughout our series:

| Criterion | APRS AX.25 ([Article 1](./article-1-aprs.en.md)) | Meshtastic ([Article 2](./article-2-flood.en.md)) | PRoPHET RFC 6693 ([Article 3](./article-3-prophet.en.md)) | Reticulum RNS ([Article 5](./article-5-reticulum.en.md)) |
| :--- | :--- | :--- | :--- | :--- |
| **Routing Paradigm** | Source routing & generic aliases | Managed flooding | Probabilistic opportunistic routing | Reactive / proactive distance-vector |
| **Addressing Format** | Amateur radio callsigns (`NOCALL-1`) | 32-bit NodeNum (`!a1b2c3d4`) | Textual EID URIs (`dtn://dest/`) | 16-byte cryptographic hashes (`dtn://rns/<hash>/`) |
| **Required DTN Wire Blocks** | Extension Block Type 200 (`trajectory_control`) | **None** (Pure standard BPv7: Type 10) | Optional Type 200 (`opportunistic_threshold`) | **None** (Pure standard BPv7: Type 10) |
| **Signaling Messages** | None (blind broadcast) | None (pre-shared channels) | Bilateral RIB & SV exchanges ([prophet.cddl](./prophet.cddl)) | Signed Announces & Path Requests ([reticulum.cddl](./reticulum.cddl)) |
| **Data Forwarding** | Broadcast multicast | General broadcast with SNR backoff | Opportunistic recommendation to favorable peers | **Strict unicast** to designated next-hop |
| **Loop Management** | Alias consumption & Type 6 Split Horizon | Deduplication via Bundle ID & Hop Count Type 10 | Transitive decay & Hop Count Type 10 | Strict hop metric & Hop Count Type 10 |
| **Partition Behavior** | Packet dropped if unrelayed | Dropped if no relay listens | Stored in memory until favorable contact | **Active DTN Custody** (Store-Carry-and-Forward) |
| **Native Security** | None (plaintext AX.25 frames) | Symmetric AES-256 channel encryption | None by default (delegated to BPSec) | **Ed25519 & Curve25519 asymmetric keys, PFS** |

---

## 9. Conclusion and Outlook

The transposition of Reticulum to Bundle Protocol v7 completes the demonstration of DTN's modularity:
1. **BPv7 Universality:** Without modifying the transport standard, BPv7 can accommodate source routing, blind flooding, probabilistic calculation, and cryptographic distance-vector routing alike.
2. **Elegance of Plane Separation:** The wire engine remains minimalist and robust; decision complexity is entirely offloaded to verifiable and auditable OPA declarative policies.
3. **Enhanced Resilience:** Reticulum brings zero-trust cryptographic addressing to DTN; DTN provides Reticulum with the indestructible persistence of *Store-Carry-and-Forward*.

In the next article ([Article 6](./article-6-babel-aredn.en.md)), we will examine proactive link-state infrastructure protocols with **AREDN (Babel / RFC 8966)** and the hybrid MANET-DTN architecture **HYMAD**!

---

👉 **Next Article:** [Article 6 — Proactive Mesh Networks and MANET-DTN Hybrids: AREDN, Babel (RFC 8966), and the HYMAD Architecture under Open Policy Agent](./article-6-babel-aredn.en.md)
