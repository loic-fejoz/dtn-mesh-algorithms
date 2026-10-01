package dtn.aprs_test

import future.keywords.if

import data.dtn.aprs.constants
import data.dtn.aprs.contact
import data.dtn.aprs.ingress

# Helper pour construire un bundle APRS mock
mock_aprs_bundle(dest, path_elements, active_idx, hash) := {
    "primary": {
        "source": "dtn://f4xyz-7/",
        "destination": dest,
        "creation_timestamp": {"time": 1000, "sequence_number": 1},
        "lifetime": 3600000,
        "processing_flags": {"deletion_report": false}
    },
    "extension_blocks": [
        {
            "block_type": 200,
            "algo_type": 1,
            "payload": {
                "active_hop_index": active_idx,
                "dupe_suppression_hash": hash,
                "allow_callsign_substitution": true,
                "path_elements": path_elements
            }
        }
    ]
}

# Nœud digipeater type : F4KXL-1
mock_digipeater_node := {
    "local_eid": "dtn://f4kxl-1/",
    "callsign": "F4KXL-1",
    "is_digipeater": true,
    "supported_aliases": ["WIDE1", "WIDE2"],
    "seen_cache": ["hash_already_seen"]
}

# 1. Test livraison locale
test_aprs_local_delivery if {
    bundle := mock_aprs_bundle("dtn://f4kxl-1/", [], 0, "hash1")
    inp := {
        "bundle": bundle,
        "node": mock_digipeater_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DELIVER_LOCAL"
}

# 2. Test suppression de doublon (Dupe cache)
test_aprs_duplicate_suppression if {
    bundle := mock_aprs_bundle("dtn://broadcast/", [], 0, "hash_already_seen")
    inp := {
        "bundle": bundle,
        "node": mock_digipeater_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Duplicate packet detected in seen cache"
}

# 3. Test Saut Strict correspondant au nœud local (F4KXL-1)
test_aprs_strict_hop_matched if {
    path := [
        {
            "hop_kind": 1,
            "node_identifier": "F4KXL-1",
            "digipeated": false
        },
        {
            "hop_kind": 2,
            "alias_name": "WIDE2",
            "max_hops": 2,
            "remaining_hops": 2,
            "digipeated": false
        }
    ]
    bundle := mock_aprs_bundle("dtn://broadcast/", path, 0, "hash_strict_match")
    inp := {
        "bundle": bundle,
        "node": mock_digipeater_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT_DIGIPEAT"
    # L'index du saut actif doit avancer à 1
    decision.mutations[0].active_hop_index == 1
    decision.mutations[0].updated_hop.digipeated == true
    decision.mutations[0].updated_hop.substituted_by == "F4KXL-1"
}

# 4. Test Saut Strict adressé à un autre digipeater (ex: F1ZAA) -> SKIP
test_aprs_strict_hop_not_for_me if {
    path := [
        {
            "hop_kind": 1,
            "node_identifier": "F1ZAA-1",
            "digipeated": false
        }
    ]
    bundle := mock_aprs_bundle("dtn://broadcast/", path, 0, "hash_strict_other")
    inp := {
        "bundle": bundle,
        "node": mock_digipeater_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "SKIP"
}

# 5. Test Alias Générique WIDE2-2 décrémenté en WIDE2-1
test_aprs_generic_alias_decremented if {
    path := [
        {
            "hop_kind": 2,
            "alias_name": "WIDE2",
            "max_hops": 2,
            "remaining_hops": 2,
            "digipeated": false
        }
    ]
    bundle := mock_aprs_bundle("dtn://broadcast/", path, 0, "hash_wide2_2")
    inp := {
        "bundle": bundle,
        "node": mock_digipeater_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT_DIGIPEAT"
    # L'index reste à 0 car il reste encore 1 saut à consommer par le prochain relais
    decision.mutations[0].active_hop_index == 0
    decision.mutations[0].updated_hop.remaining_hops == 1
    decision.mutations[0].updated_hop.substituted_by == "F4KXL-1"
}

# 6. Test Alias Générique WIDE1-1 consommé (0 saut restant)
test_aprs_generic_alias_fully_consumed if {
    path := [
        {
            "hop_kind": 2,
            "alias_name": "WIDE1",
            "max_hops": 1,
            "remaining_hops": 1,
            "digipeated": false
        },
        {
            "hop_kind": 2,
            "alias_name": "WIDE2",
            "max_hops": 2,
            "remaining_hops": 2,
            "digipeated": false
        }
    ]
    bundle := mock_aprs_bundle("dtn://broadcast/", path, 0, "hash_wide1_1")
    inp := {
        "bundle": bundle,
        "node": mock_digipeater_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT_DIGIPEAT"
    # L'index doit maintenant pointer vers le saut 1 (le WIDE2 suivant)
    decision.mutations[0].active_hop_index == 1
    decision.mutations[0].updated_hop.remaining_hops == 0
    decision.mutations[0].updated_hop.digipeated == true
    decision.mutations[0].updated_hop.substituted_by == "F4KXL-1"
}

# 7. Test Alias non pris en charge (ex: WIDE3) -> SKIP
test_aprs_unsupported_alias if {
    path := [
        {
            "hop_kind": 2,
            "alias_name": "WIDE3",
            "max_hops": 3,
            "remaining_hops": 3,
            "digipeated": false
        }
    ]
    bundle := mock_aprs_bundle("dtn://broadcast/", path, 0, "hash_wide3")
    inp := {
        "bundle": bundle,
        "node": mock_digipeater_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "SKIP"
}

# 8. Test Contact Broadcast
test_aprs_contact_broadcast if {
    bundle := mock_aprs_bundle("dtn://broadcast/", [], 0, "hash_contact")
    inp := {
        "bundle": bundle,
        "node": mock_digipeater_node,
        "contact": {
            "is_broadcast": true,
            "cla_type": "ax25"
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_BROADCAST"
}

# 9. Test Contact Unicast vers le prochain saut strict
test_aprs_contact_unicast_match if {
    path := [
        {
            "hop_kind": 1,
            "node_identifier": "dtn://f1zaa-1/",
            "digipeated": false
        }
    ]
    bundle := mock_aprs_bundle("dtn://broadcast/", path, 0, "hash_unicast")
    inp := {
        "bundle": bundle,
        "node": mock_digipeater_node,
        "contact": {
            "is_broadcast": false,
            "peer_eid": "dtn://f1zaa-1/",
            "cla_type": "ax25"
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_UNICAST"
}

# 10. Test Recommandation Dire Wolf 6.1(b) : Rejet d'un paquet émis par le nœud local lui-même
test_aprs_direwolf_6_1b_suppress_own_packet if {
    bundle := {
        "primary": {
            "source": "dtn://f4kxl-1/", # Émis par la station locale elle-même
            "destination": "dtn://broadcast/",
            "creation_timestamp": {"time": 1000, "sequence_number": 1},
            "lifetime": 3600000,
            "processing_flags": {"deletion_report": false}
        },
        "extension_blocks": [
            {
                "block_type": 200,
                "algo_type": 1,
                "payload": {
                    "active_hop_index": 0,
                    "dupe_suppression_hash": "hash_own",
                    "allow_callsign_substitution": true,
                    "path_elements": [
                        {
                            "hop_kind": 2,
                            "alias_name": "WIDE1",
                            "max_hops": 1,
                            "remaining_hops": 1,
                            "digipeated": false
                        }
                    ]
                }
            }
        ]
    }
    inp := {
        "bundle": bundle,
        "node": mock_digipeater_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Packet originated from local station (Dire Wolf rule 6.1b)"
}

# 11. Test Recommandation Dire Wolf 6.3(c) : Rejet d'un alias dont le compte de sauts restant est déjà 0
test_aprs_direwolf_6_3c_drop_exhausted_alias if {
    path := [
        {
            "hop_kind": 2,
            "alias_name": "WIDE1",
            "max_hops": 1,
            "remaining_hops": 0, # Anormalement à 0 mais non marqué digipeated (ex: TNC défectueux)
            "digipeated": false
        }
    ]
    bundle := mock_aprs_bundle("dtn://broadcast/", path, 0, "hash_n0")
    inp := {
        "bundle": bundle,
        "node": mock_digipeater_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Generic alias hop count exhausted (N=0, Dire Wolf rule 6.3c)"
}

# 12. Test Recommandation Dire Wolf Section 10 : Trapping des alias excessifs (WIDE3-3 clampé à 1 saut)
test_aprs_direwolf_section_10_trapping_excessive_alias if {
    node_with_trapping := object.union(mock_digipeater_node, {
        "trapped_aliases": ["WIDE3", "WIDE4"]
    })
    path := [
        {
            "hop_kind": 2,
            "alias_name": "WIDE3",
            "max_hops": 3,
            "remaining_hops": 3, # Requiert 3 sauts, mais doit être piégé/clampé à un seul
            "digipeated": false
        }
    ]
    bundle := mock_aprs_bundle("dtn://broadcast/", path, 0, "hash_wide3_trapped")
    inp := {
        "bundle": bundle,
        "node": node_with_trapping,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT_DIGIPEAT"
    # L'alias est consommé d'un coup (remaining_hops = 0, digipeated = true, et l'index avance)
    decision.mutations[0].active_hop_index == 1
    decision.mutations[0].updated_hop.remaining_hops == 0
    decision.mutations[0].updated_hop.digipeated == true
    decision.mutations[0].updated_hop.substituted_by == "F4KXL-1"
}

# 13. Test Trajectoire avec le schéma CDDL Générique (trajectory_control / scoped_alias)
test_aprs_generic_cddl_trajectory if {
    bundle := {
        "primary": {
            "source": "dtn://sensor1/",
            "destination": "dtn://broadcast/",
            "creation_timestamp": {"time": 1000, "sequence_number": 1},
            "lifetime": 3600000,
            "processing_flags": {"deletion_report": false}
        },
        "extension_blocks": [
            {
                "block_type": 200,
                "payload": {
                    "transaction_id": "gen_cddl_1",
                    "trajectory_control": {
                        "active_hop_index": 0,
                        "path_elements": [
                            {
                                "target_type": 2,
                                "scope_name": "WIDE1",
                                "max_count": 1,
                                "remaining_count": 1,
                                "completed": false
                            }
                        ]
                    }
                }
            }
        ]
    }
    inp := {
        "bundle": bundle,
        "node": mock_digipeater_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT_DIGIPEAT"
    decision.mutations[0].active_hop_index == 1
}

