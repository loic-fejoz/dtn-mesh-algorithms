package dtn.contact_test

import future.keywords.if

import data.dtn.constants
import data.dtn.contact

# Test 1 : Le bundle a expiré avant l'opportunité de contact
test_contact_drop_expired if {
    inp := {
        "bundle": {
            "primary": {
                "source": "dtn://sensor1/",
                "destination": "dtn://node-c/",
                "creation_timestamp": {"time": 1000, "sequence_number": 1},
                "lifetime": 2000,
                "processing_flags": {"deletion_report": true}
            },
            "extension_blocks": []
        },
        "node": {"local_eid": "dtn://node-a/"},
        "contact": {
            "peer_eid": "dtn://node-b/",
            "cla_type": "tcpcl"
        },
        "current_dtn_time_ms": 3500
    }
    decision := contact.decision with input as inp
    decision.action == "DROP"
    decision.reason_code == constants.reason_lifetime_expired
    decision.generate_status_report == true
}

# Test 2 : Le hop count a atteint la limite avant émission (RFC 9171 Section 4.3.3)
test_contact_drop_hop_limit_reached if {
    inp := {
        "bundle": {
            "primary": {
                "source": "dtn://sensor1/",
                "destination": "dtn://node-c/",
                "creation_timestamp": {"time": 1000, "sequence_number": 1},
                "lifetime": 10000,
                "processing_flags": {"deletion_report": true}
            },
            "extension_blocks": [
                {
                    "block_type": constants.block_type_hop_count,
                    "hop_count": 5,
                    "hop_limit": 5
                }
            ]
        },
        "node": {"local_eid": "dtn://node-a/"},
        "contact": {
            "peer_eid": "dtn://node-b/",
            "cla_type": "tcpcl"
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "DROP"
    decision.reason_code == constants.reason_hop_limit_exceeded
    decision.generate_status_report == true
}

# Test 3 : Évitement de boucle - ne pas renvoyer au nœud précédent (Type 6)
test_contact_skip_previous_node if {
    inp := {
        "bundle": {
            "primary": {
                "source": "dtn://sensor1/",
                "destination": "dtn://node-c/",
                "creation_timestamp": {"time": 1000, "sequence_number": 1},
                "lifetime": 10000,
                "processing_flags": {"deletion_report": false}
            },
            "extension_blocks": [
                {
                    "block_type": constants.block_type_previous_node,
                    "previous_node": "dtn://node-b/"
                }
            ]
        },
        "node": {"local_eid": "dtn://node-a/"},
        "contact": {
            "peer_eid": "dtn://node-b/",
            "cla_type": "tcpcl"
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "SKIP"
    decision.reason == "Peer is the previous sender (split-horizon / loop avoidance)"
}

# Test 4 : Transmission directe si le contact est la destination finale
test_contact_forward_direct_destination if {
    inp := {
        "bundle": {
            "primary": {
                "source": "dtn://sensor1/",
                "destination": "dtn://destination-node/",
                "creation_timestamp": {"time": 1000, "sequence_number": 1},
                "lifetime": 10000,
                "processing_flags": {"deletion_report": false}
            },
            "extension_blocks": []
        },
        "node": {"local_eid": "dtn://node-a/"},
        "contact": {
            "peer_eid": "dtn://destination-node/",
            "cla_type": "lora"
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD"
    decision.reason == "Peer is the final destination"
}

# Test 5 : Transmission opportuniste vers un relais intermédiaire valide
test_contact_forward_opportunistic_relay if {
    inp := {
        "bundle": {
            "primary": {
                "source": "dtn://sensor1/",
                "destination": "dtn://destination-node/",
                "creation_timestamp": {"time": 1000, "sequence_number": 1},
                "lifetime": 10000,
                "processing_flags": {"deletion_report": false}
            },
            "extension_blocks": [
                {
                    "block_type": constants.block_type_previous_node,
                    "previous_node": "dtn://node-upstream/"
                }
            ]
        },
        "node": {"local_eid": "dtn://node-a/"},
        "contact": {
            "peer_eid": "dtn://node-relay/",
            "cla_type": "bluetooth"
        },
        "current_dtn_time_ms": 2000
    }
    decision := contact.decision with input as inp
    decision.action == "FORWARD"
    decision.reason == "Peer is an eligible relay for opportunistic forwarding"
}
