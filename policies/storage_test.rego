package dtn.storage_test

import future.keywords.if

import data.dtn.constants
import data.dtn.storage

# Test 1 : Suppression d'un bundle dont la durée de vie a expiré pendant le stockage (horloge synchronisée)
test_storage_drop_lifetime_expired_timed if {
    inp := {
        "bundle": {
            "primary": {
                "source": "dtn://sensor1/",
                "destination": "dtn://remote/",
                "creation_timestamp": {"time": 1000, "sequence_number": 1},
                "lifetime": 3000,
                "processing_flags": {"deletion_report": true}
            },
            "extension_blocks": []
        },
        "node": {"local_eid": "dtn://node-a/"},
        "current_dtn_time_ms": 4500,
        "elapsed_since_last_audit_ms": 1000
    }
    decision := storage.decision with input as inp
    decision.action == "DROP"
    decision.reason_code == constants.reason_lifetime_expired
    decision.generate_status_report == true
}

# Test 2 : Suppression d'un bundle dont la durée de vie a expiré (untimed avec Age Block)
test_storage_drop_lifetime_expired_untimed if {
    inp := {
        "bundle": {
            "primary": {
                "source": "dtn://sensor1/",
                "destination": "dtn://remote/",
                "creation_timestamp": {"time": 0, "sequence_number": 1},
                "lifetime": 10000,
                "processing_flags": {"deletion_report": false}
            },
            "extension_blocks": [
                {
                    "block_type": constants.block_type_bundle_age,
                    "bundle_age_ms": 11000
                }
            ]
        },
        "node": {"local_eid": "dtn://node-a/"},
        "current_dtn_time_ms": 50000,
        "elapsed_since_last_audit_ms": 1000
    }
    decision := storage.decision with input as inp
    decision.action == "DROP"
    decision.reason_code == constants.reason_lifetime_expired
}

# Test 3 : Conservation d'un bundle encore valide et incrémentation de son âge
test_storage_retain_and_update_age if {
    inp := {
        "bundle": {
            "primary": {
                "source": "dtn://sensor1/",
                "destination": "dtn://remote/",
                "creation_timestamp": {"time": 0, "sequence_number": 1},
                "lifetime": 10000,
                "processing_flags": {"deletion_report": false}
            },
            "extension_blocks": [
                {
                    "block_type": constants.block_type_bundle_age,
                    "bundle_age_ms": 2000
                }
            ]
        },
        "node": {"local_eid": "dtn://node-a/"},
        "current_dtn_time_ms": 50000,
        "elapsed_since_last_audit_ms": 3000
    }
    decision := storage.decision with input as inp
    decision.action == "RETAIN"
    decision.mutations[0].block_type == constants.block_type_bundle_age
    decision.mutations[0].value == 3000
}
