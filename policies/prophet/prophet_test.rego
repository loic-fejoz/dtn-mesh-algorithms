package dtn.prophet_test

import future.keywords.if
import future.keywords.in

import data.dtn.prophet.constants
import data.dtn.prophet.contact
import data.dtn.prophet.helpers
import data.dtn.prophet.ingress
import data.dtn.prophet.storage

# Mock du nœud local A
mock_node := {
    "local_eid": "dtn://node-a/",
    "delivery_predictabilities": {
        "dtn://node-dest/": 0.3,
        "dtn://node-c/": 0.2,
        "dtn://node-cold/": 0.05
    },
    "seen_cache": [
        ["dtn://source-seen/", 1000, 1]
    ],
    "storage_used_bytes": 500,
    "storage_capacity_bytes": 1000,
    "eviction_predictability_threshold": 0.1
}

# Helper pour construire des bundles de test
mock_bundle(dest, lifetime, has_hcb, threshold) := bundle if {
    eblocks_base := [
        {
            "block_type": 10,
            "hop_count": 1,
            "hop_limit": 5
        } | has_hcb
    ]
    eblocks_thresh := [
        {
            "block_type": 200,
            "payload": {
                "opportunistic_threshold": threshold
            }
        } | threshold != null
    ]
    bundle := {
        "primary": {
            "source": "dtn://source-node/",
            "destination": dest,
            "creation_timestamp": {"time": 1000, "sequence_number": 42},
            "lifetime": lifetime,
            "processing_flags": {"deletion_report": false}
        },
        "extension_blocks": array.concat(eblocks_base, eblocks_thresh)
    }
}

# 1. Test mathématique : Mise à jour de rencontre directe P(a, b)
test_prophet_math_encounter if {
    # P_old = 0.5, P_encounter = 0.75 -> 0.5 + (0.5 * 0.75) = 0.875
    p_new := helpers.update_encounter(0.5, 0.75)
    p_new == 0.875
}

# 2. Test mathématique : Vieillissement temporel P(a, b) * gamma^k
test_prophet_math_aging if {
    # P_old = 0.8, gamma = 0.9, k = 2 -> 0.8 * 0.81 = 0.648
    p_aged := helpers.update_aging(0.8, 0.9, 2)
    # Vérification avec tolérance pour virgule flottante
    p_aged > 0.6479
    p_aged < 0.6481
}

# 3. Test mathématique : Transitivité P(a, c)
test_prophet_math_transitivity if {
    # P_ac_old = 0.2, P_ab = 0.8, P_bc = 0.5, beta = 0.5
    # transitive_factor = 0.8 * 0.5 * 0.5 = 0.2
    # P_ac_new = 0.2 + (0.8 * 0.2) = 0.36
    p_trans := helpers.update_transitivity(0.2, 0.8, 0.5, 0.5)
    p_trans > 0.3599
    p_trans < 0.3601
}

# 4. Ingress : Délivrance locale si destination == local_eid
test_prophet_ingress_local_delivery if {
    bundle := mock_bundle("dtn://node-a/", 3600000, true, null)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DELIVER_LOCAL"
}

# 5. Ingress : Détection de doublon
test_prophet_ingress_duplicate if {
    bundle := {
        "primary": {
            "source": "dtn://source-seen/",
            "destination": "dtn://other-dest/",
            "creation_timestamp": {"time": 1000, "sequence_number": 1},
            "lifetime": 3600000
        },
        "extension_blocks": []
    }
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Duplicate bundle detected in seen cache"
}

# 6. Ingress : Dépassement de la durée de vie
test_prophet_ingress_expired if {
    bundle := mock_bundle("dtn://node-dest/", 1000, true, null) # Expire à 2000
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2500
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Bundle lifetime expired"
}

# 7. Ingress : Acceptation normale et incrémentation de hop_count
test_prophet_ingress_accept_increment if {
    bundle := mock_bundle("dtn://node-dest/", 3600000, true, null)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT"
    decision.mutations[0].new_hop_count == 2
}

# 8. Contact : Contact direct avec la destination finale
test_prophet_contact_direct_destination if {
    bundle := mock_bundle("dtn://node-dest/", 3600000, true, null)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://node-dest/",
            "held_bundle_ids": []
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_DIRECT"
}

# 9. Contact : Ignorer le pair si Summary Vector indique qu'il l'a déjà
test_prophet_contact_skip_peer_holds if {
    bundle := mock_bundle("dtn://node-dest/", 3600000, true, null)
    bundle_id := ["dtn://source-node/", 1000, 42]
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://node-b/",
            "peer_predictabilities": {"dtn://node-dest/": 0.9},
            "held_bundle_ids": [bundle_id]
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "SKIP"
    decision.reason == "Peer already holds this bundle in summary vector"
}

# 10. Contact : Forwarding opportuniste favorable P(peer) > P(local)
# P(local, dest) = 0.3, P(peer, dest) = 0.75
test_prophet_contact_forward_favorable if {
    bundle := mock_bundle("dtn://node-dest/", 3600000, true, null)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://node-b/",
            "peer_predictabilities": {"dtn://node-dest/": 0.75},
            "held_bundle_ids": []
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_OPPORTUNISTIC"
}

# 11. Contact : Refus d'acheminement si P(peer) <= P(local)
# P(local, dest) = 0.3, P(peer, dest) = 0.15
test_prophet_contact_skip_unfavorable if {
    bundle := mock_bundle("dtn://node-dest/", 3600000, true, null)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://node-b/",
            "peer_predictabilities": {"dtn://node-dest/": 0.15},
            "held_bundle_ids": []
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "SKIP"
}

# 12. Contact : Seuil opportuniste non satisfait par le pair
# Bundle exige un seuil de 0.8. Le pair offre 0.6 (> P_local 0.3) mais 0.6 < 0.8 -> SKIP
test_prophet_contact_skip_threshold_unmet if {
    bundle := mock_bundle("dtn://node-dest/", 3600000, true, 0.8)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://node-b/",
            "peer_predictabilities": {"dtn://node-dest/": 0.6},
            "held_bundle_ids": []
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "SKIP"
    contains(decision.reason, "does not meet bundle threshold")
}

# 13. Contact : Seuil opportuniste satisfait par le pair
# Bundle exige un seuil de 0.6. Le pair offre 0.85 -> FORWARD_OPPORTUNISTIC
test_prophet_contact_forward_threshold_met if {
    bundle := mock_bundle("dtn://node-dest/", 3600000, true, 0.6)
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "contact": {
            "peer_eid": "dtn://node-b/",
            "peer_predictabilities": {"dtn://node-dest/": 0.85},
            "held_bundle_ids": []
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD_OPPORTUNISTIC"
}

# 14. Storage : Élimination périodique des bundles expirés
test_prophet_storage_drop_expired if {
    bundle := mock_bundle("dtn://node-dest/", 1000, true, null) # Expire à 2000
    inp := {
        "bundle": bundle,
        "node": mock_node,
        "current_dtn_time_ms": 3000,
        "elapsed_since_last_audit_ms": 1000
    }
    decision := storage.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Lifetime expired during storage audit"
}

# 15. Storage : Éviction en cas de saturation de buffer (faible prévisibilité)
# Mémoire utilisée 1200 > capacité 1000, P(local, cold) = 0.05 <= 0.10
test_prophet_storage_eviction_low_predictability if {
    bundle := mock_bundle("dtn://node-cold/", 3600000, true, null)
    node_full := object.union(mock_node, {
        "storage_used_bytes": 1200,
        "storage_capacity_bytes": 1000
    })
    inp := {
        "bundle": bundle,
        "node": node_full,
        "current_dtn_time_ms": 2000,
        "elapsed_since_last_audit_ms": 500
    }
    decision := storage.decision with input as inp
    decision.action == "EVICT_LOW_PREDICTABILITY"
    decision.eviction_metric == 0.05
}

# 16. Storage : Rétention en cas de saturation si la prévisibilité est forte
# P(local, dest) = 0.3 > seuil d'éviction 0.10
test_prophet_storage_retain_high_predictability if {
    bundle := mock_bundle("dtn://node-dest/", 3600000, true, null)
    node_full := object.union(mock_node, {
        "storage_used_bytes": 1200,
        "storage_capacity_bytes": 1000
    })
    inp := {
        "bundle": bundle,
        "node": node_full,
        "current_dtn_time_ms": 2000,
        "elapsed_since_last_audit_ms": 500
    }
    decision := storage.decision with input as inp
    decision.action == "RETAIN"
}
