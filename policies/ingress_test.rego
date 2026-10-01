package dtn.ingress_test

import future.keywords.if

import data.dtn.constants
import data.dtn.ingress

# Helper pour construire un bundle de test
mock_bundle(dest, creation_time, lifetime, hop_count, hop_limit, request_deletion_report) := {
    "primary": {
        "source": "dtn://sensor1/",
        "destination": dest,
        "creation_timestamp": {
            "time": creation_time,
            "sequence_number": 1
        },
        "lifetime": lifetime,
        "processing_flags": {
            "deletion_report": request_deletion_report
        }
    },
    "extension_blocks": [
        {
            "block_type": constants.block_type_hop_count,
            "hop_count": hop_count,
            "hop_limit": hop_limit
        }
    ]
}

# Test 1 : Livraison locale si la destination est le nœud local
test_ingress_local_delivery if {
    bundle := mock_bundle("dtn://local-node/", 1000, 5000, 1, 5, false)
    inp := {
        "bundle": bundle,
        "node": {"local_eid": "dtn://local-node/"},
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DELIVER_LOCAL"
}

# Test 2 : Suppression si la lifetime a expiré (horloge synchronisée)
test_ingress_drop_lifetime_expired_timed if {
    # creation 1000 + lifetime 2000 = expiration à 3000. current_time = 3500
    bundle := mock_bundle("dtn://remote-node/", 1000, 2000, 1, 5, true)
    inp := {
        "bundle": bundle,
        "node": {"local_eid": "dtn://local-node/"},
        "current_dtn_time_ms": 3500
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason_code == constants.reason_lifetime_expired
    decision.generate_status_report == true
}

# Test 3 : Suppression si la lifetime a expiré (nœud non synchronisé avec Bundle Age Block)
test_ingress_drop_lifetime_expired_untimed if {
    bundle := {
        "primary": {
            "source": "dtn://sensor1/",
            "destination": "dtn://remote-node/",
            "creation_timestamp": {"time": 0, "sequence_number": 1},
            "lifetime": 10000,
            "processing_flags": {"deletion_report": false}
        },
        "extension_blocks": [
            {
                "block_type": constants.block_type_bundle_age,
                "bundle_age_ms": 12000
            }
        ]
    }
    inp := {
        "bundle": bundle,
        "node": {"local_eid": "dtn://local-node/"},
        "current_dtn_time_ms": 999999
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason_code == constants.reason_lifetime_expired
}

# Test 4 : Suppression si le hop count atteint ou dépasse la limite à la réception
test_ingress_drop_hop_limit_reached if {
    # hop_count = 4, hop_limit = 5. À l'ingress, (4 + 1) = 5 >= hop_limit -> DROP (RFC 9171)
    bundle := mock_bundle("dtn://remote-node/", 1000, 10000, 4, 5, true)
    inp := {
        "bundle": bundle,
        "node": {"local_eid": "dtn://local-node/"},
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason_code == constants.reason_hop_limit_exceeded
    decision.generate_status_report == true
}

# Test 5 : Acceptation du bundle en transit et incrément du hop count
test_ingress_accept_and_mutate_hop_count if {
    # hop_count = 2, hop_limit = 5. (2 + 1) = 3 < 5 -> ACCEPT avec mutation hop_count = 3
    bundle := mock_bundle("dtn://remote-node/", 1000, 10000, 2, 5, false)
    inp := {
        "bundle": bundle,
        "node": {"local_eid": "dtn://local-node/"},
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "ACCEPT"
    decision.mutations[0].block_type == constants.block_type_hop_count
    decision.mutations[0].value == 3
}

# Test 6 : Rejet immédiat si la source est blacklistée (Anti-Spam / DoS)
test_ingress_drop_blacklisted_source if {
    bundle := mock_bundle("dtn://remote-node/", 1000, 10000, 1, 5, true)
    inp := {
        "bundle": bundle,
        "node": {
            "local_eid": "dtn://local-node/",
            "blacklist_sources": ["dtn://sensor1/", "dtn://malicious-node/"]
        },
        "current_dtn_time_ms": 2000
    }
    decision := ingress.decision with input as inp
    decision.action == "DROP"
    decision.reason == "Source EID is blacklisted on this node"
    decision.generate_status_report == false
}
