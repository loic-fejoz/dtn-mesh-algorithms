package dtn.flood_test

import future.keywords.if

import data.dtn.flood.constants
import data.dtn.flood.contact
import data.dtn.flood.ingress

# Helper pour construire un bundle Spray & Wait mock
mock_spray_bundle(dest, quota, mode, msg_id) := {
    "primary": {
        "source": "dtn://sensor1/",
        "destination": dest,
        "creation_timestamp": {"time": 1000, "sequence_number": 1},
        "lifetime": 3600000,
        "processing_flags": {"deletion_report": false}
    },
    "extension_blocks": [
        {
            "block_type": 200,
            "algo_type": 2,
            "payload": {
                "replication_quota": quota,
                "spray_mode": mode,
                "generation": 1,
                "message_id": msg_id
            }
        }
    ]
}

# Helper pour construire un bundle de diffusion pur BPv7 (style Meshtastic avec Hop Count Block Type 10)
mock_meshtastic_bundle(packet_id, snr_db) := mock_meshtastic_bundle_hops(packet_id, snr_db, 0, 3)

mock_meshtastic_bundle_hops(packet_id, snr_db, hop_count, hop_limit) := {
    "primary": {
        "source": "dtn://node-mesh-1/",
        "destination": "dtn://broadcast/",
        "creation_timestamp": {"time": 1000, "sequence_number": 1},
        "lifetime": 3600000,
        "processing_flags": {"deletion_report": false}
    },
    "extension_blocks": [
        {
            "block_type": 10, # Standard BPv7 Hop Count Block (RFC 9171)
            "hop_count": hop_count,
            "hop_limit": hop_limit
        },
        {
            "block_type": 200,
            "payload": {
                "legacy_bridge_id": packet_id
            }
        }
    ]
}

mock_node := {
    "local_eid": "dtn://node-local/",
    "allowed_destinations": ["dtn://broadcast/", "dtn://remote/", "dtn://node-local/"],
    "seen_cache": ["already_seen_msg", 999],
    "cancelled_rebroadcasts": [888]
}

# 1. Livraison locale
test_flood_local_delivery if {
    bundle := mock_spray_bundle("dtn://node-local/", 8, constants.spray_mode_binary, "m1")
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DELIVER_LOCAL"
}

# 2. Rejet de doublon (Flooding / Epidemic loop prevention)
test_flood_duplicate_suppression if {
    bundle := mock_spray_bundle("dtn://remote/", 8, constants.spray_mode_binary, "already_seen_msg")
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Duplicate message detected in seen cache"
}

# 3. Spray & Wait Ingress : Acceptation et enregistrement en phase SPRAY (L > 1)
test_spray_ingress_spray_phase if {
    bundle := mock_spray_bundle("dtn://remote/", 4, constants.spray_mode_binary, "m_new")
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT_STORE"
    decision.mutations[0].phase == constants.phase_spray
    decision.mutations[0].quota == 4
}

# 4. Spray & Wait Ingress : Acceptation et bascule immédiate en phase WAIT (L = 1)
test_spray_ingress_wait_phase if {
    bundle := mock_spray_bundle("dtn://remote/", 1, constants.spray_mode_binary, "m_wait")
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT_STORE"
    decision.mutations[0].phase == constants.phase_wait
    decision.mutations[0].quota == 1
}

# 5. Spray & Wait Contact : Contact direct avec la destination finale (Prioritaire même en phase Wait)
test_spray_contact_direct_destination if {
    bundle := mock_spray_bundle("dtn://dest-node/", 1, constants.spray_mode_binary, "m_direct")
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://dest-node/",
            "held_bundle_ids": []
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_DIRECT"
}

# 6. Spray & Wait Contact : Ignorer un relais qui détient déjà une copie (Summary Vector)
test_spray_contact_skip_peer_already_holds if {
    bundle := mock_spray_bundle("dtn://remote/", 4, constants.spray_mode_binary, "m_held")
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://relay-node/",
            "held_bundle_ids": ["m_held"]
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "SKIP"
    decision.reason == "Peer already holds a copy of this bundle (summary vector check)"
}

# 7. Spray & Wait Contact : Binary Spray avec quota pair (L=8 -> Transmet 4, garde 4)
test_spray_contact_binary_split_even if {
    bundle := mock_spray_bundle("dtn://remote/", 8, constants.spray_mode_binary, "m_even")
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://relay-node/",
            "held_bundle_ids": []
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_REPLICATE"
    decision.mutations[0].transmitted_quota == 4
    decision.mutations[0].transmitted_phase == constants.phase_spray
    decision.mutations[0].local_quota == 4
    decision.mutations[0].local_phase == constants.phase_spray
}

# 8. Spray & Wait Contact : Binary Spray avec L=2 (Transmet 1 -> Wait sur pair, garde 1 -> Wait local)
test_spray_contact_binary_split_to_wait if {
    bundle := mock_spray_bundle("dtn://remote/", 2, constants.spray_mode_binary, "m_two")
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://relay-node/",
            "held_bundle_ids": []
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_REPLICATE"
    decision.mutations[0].transmitted_quota == 1
    decision.mutations[0].transmitted_phase == constants.phase_wait
    decision.mutations[0].local_quota == 1
    decision.mutations[0].local_phase == constants.phase_wait
}

# 9. Spray & Wait Contact : Source Spray avec L=5 -> Transmet 1, garde 4
test_spray_contact_source_spray if {
    bundle := mock_spray_bundle("dtn://remote/", 5, constants.spray_mode_source, "m_src5")
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://relay-node/",
            "held_bundle_ids": []
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_REPLICATE"
    decision.mutations[0].transmitted_quota == 1
    decision.mutations[0].transmitted_phase == constants.phase_wait
    decision.mutations[0].local_quota == 4
    decision.mutations[0].local_phase == constants.phase_spray
}

# 10. Spray & Wait Contact : En phase WAIT (L=1), refus de transmettre à un relais
test_spray_contact_wait_phase_skip_relay if {
    bundle := mock_spray_bundle("dtn://remote/", 1, constants.spray_mode_binary, "m_wait1")
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://relay-node/",
            "held_bundle_ids": []
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "SKIP"
    decision.reason == "Spray & Wait bundle is in WAIT phase (L=1): awaiting direct destination contact only"
}

# 11. Ingress Radio : Calcul du délai de contention SNR et incrémentation hop_count
test_meshtastic_ingress_channel_match_and_backoff if {
    bundle := mock_meshtastic_bundle(101, -5.0)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "ingress": {"snr_db": -5.0},
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT_REBROADCAST"
    # SNR = -5 -> clamped = (-5 + 15) = 10 -> backoff = 200 + 10*50 = 700 ms
    decision.mutations[0].backoff_delay_ms == 700
    decision.mutations[1].value == 1
}

# 12. Ingress Radio : Rejet si l'EID de destination n'est pas dans la whitelist du nœud
test_meshtastic_ingress_channel_mismatch if {
    bundle := {
        "primary": {
            "source": "dtn://node-mesh-1/",
            "destination": "dtn://forbidden-channel/", # Non présent dans allowed_destinations
            "creation_timestamp": {"time": 1000, "sequence_number": 1},
            "lifetime": 3600000,
            "processing_flags": {"deletion_report": false}
        },
        "extension_blocks": []
    }
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "ingress": {"snr_db": 0.0},
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Destination EID not allowed by local node whitelist"
}

# 13. Meshtastic Contact : Annulation si entendu pendant la fenêtre de contention
test_meshtastic_contact_cancelled_during_backoff if {
    bundle := mock_meshtastic_bundle(888, 0.0) # 888 est dans cancelled_rebroadcasts
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://broadcast/",
            "is_broadcast": true
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "SKIP"
    decision.reason == "Meshtastic rebroadcast cancelled: packet heard from another peer during backoff"
}

# 14. Meshtastic Contact : Rediffusion radio autorisée si non annulé
test_meshtastic_contact_broadcast_success if {
    bundle := mock_meshtastic_bundle(777, 0.0)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://broadcast/",
            "is_broadcast": true
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_BROADCAST"
    decision.reason == "Packet ready for radio rebroadcast"
}

# 15. Meshtastic Ingress : Rejet si le Hop Count Block (Type 10) a déjà atteint sa limite
test_meshtastic_ingress_hop_limit_reached if {
    # hop_count = 3, hop_limit = 3 -> will_exceed_hop_limit == true
    bundle := mock_meshtastic_bundle_hops(103, 5.0, 3, 3)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "ingress": {"snr_db": 5.0},
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Hop limit exceeded (BPv7 Hop Count Block Type 10)"
}

# 16. Test Réplication avec le schéma CDDL Générique (replication_control)
test_flood_generic_cddl_replication if {
    bundle := {
        "primary": {
            "source": "dtn://source-node/",
            "destination": "dtn://remote-dest/",
            "creation_timestamp": {"time": 1000, "sequence_number": 1},
            "lifetime": 3600000,
            "processing_flags": {"deletion_report": false}
        },
        "extension_blocks": [
            {
                "block_type": 200,
                "payload": {
                    "legacy_bridge_id": 12345,
                    "replication_control": {
                        "quota": 6,
                        "mode": 2, # Binary
                        "phase": 1 # Spray
                    }
                }
            }
        ]
    }
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://relay-node/",
            "held_bundle_ids": []
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_REPLICATE"
    decision.mutations[0].transmitted_quota == 3
    decision.mutations[0].local_quota == 3
}

# 17. Test Diffusion Pure BPv7 sans bloc d'extension custom (Calcul SNR backoff & incrément Hop Count)
test_flood_generic_cddl_wireless if {
    bundle := {
        "primary": {
            "source": "dtn://node-lora/",
            "destination": "dtn://broadcast/",
            "creation_timestamp": {"time": 1000, "sequence_number": 1},
            "lifetime": 3600000,
            "processing_flags": {"deletion_report": false}
        },
        "extension_blocks": [
            {
                "block_type": 10,
                "hop_count": 0,
                "hop_limit": 5
            }
        ]
    }
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "ingress": {"snr_db": -10.0},
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT_REBROADCAST"
    # SNR = -10 -> clamped = (-10 + 15) = 5 -> backoff = 200 + 5*50 = 450 ms
    decision.mutations[0].backoff_delay_ms == 450
    decision.mutations[1].value == 1
}
