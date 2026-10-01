package dtn.maxprop_test

import future.keywords.if
import future.keywords.in

import data.dtn.maxprop.ingress
import data.dtn.maxprop.contact
import data.dtn.maxprop.storage
import data.dtn.maxprop.constants

mock_data_bundle(src, dest, hops, dijkstra_cost) := {
    "primary": {
        "version": 7,
        "bundle_processing_control_flags": 0,
        "destination": dest,
        "source": src,
        "report_to": src,
        "creation_timestamp": {"time": 1000, "sequence_number": 1},
        "lifetime": 3600000,
        "processing_flags": {"deletion_report": false}
    },
    "extension_blocks": [
        {
            "block_type": 10,
            "hop_limit": 15,
            "hop_count": hops
        }
    ],
    "dijkstra_cost": dijkstra_cost
}

mock_cleared_list_bundle(cleared_ids) := {
    "primary": {
        "version": 7,
        "bundle_processing_control_flags": 0,
        "destination": constants.maxprop_broadcast_eid,
        "source": "dtn://sender/cleared-issuer/",
        "report_to": "dtn://none",
        "creation_timestamp": {"time": 1000, "sequence_number": 2},
        "lifetime": 60000,
        "processing_flags": {"deletion_report": false}
    },
    "extension_blocks": [{
        "block_type": 10,
        "hop_limit": 5,
        "hop_count": 0
    }],
    "cleared_list": cleared_ids
}

# 1. Ingress : Livraison locale si la destination correspond à l'EID local
test_maxprop_ingress_local_delivery if {
    input := {
        "bundle": mock_data_bundle("dtn://sender/", "dtn://local-node/", 2, 0.5),
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://local-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "DELIVER_LOCAL"
}

# 2. Ingress : Rejet silencieux si la source est blacklistée
test_maxprop_ingress_blacklisted_source if {
    input := {
        "bundle": mock_data_bundle("dtn://bad-node/", "dtn://other-dest/", 2, 0.5),
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://local-node/",
            "blacklist_sources": ["dtn://bad-node/"]
        }
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    decision.generate_status_report == false
}

# 3. Ingress : Rejet des doublons déjà observés
test_maxprop_ingress_duplicate if {
    bundle := mock_data_bundle("dtn://sender/", "dtn://other-dest/", 2, 0.5)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://local-node/",
            "seen_cache": ["dtn://sender/:1000:1"]
        }
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    decision.reason == "Duplicate bundle detected in seen cache"
}

# 4. Ingress : Rejet si le bundle figure dans la Cleared List (déjà livré)
test_maxprop_ingress_cleared_bundle_dropped if {
    bundle := mock_data_bundle("dtn://sender/", "dtn://other-dest/", 2, 0.5)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://local-node/",
            "cleared_list": ["dtn://sender/:1000:1"]
        }
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    contains(decision.reason, "Cleared List")
}

# 5. Ingress : Rejet si la durée de vie a expiré
test_maxprop_ingress_expired if {
    bundle := mock_data_bundle("dtn://sender/", "dtn://other-dest/", 2, 0.5)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 1000 + 3600000 + 10,
        "node": {"local_eid": "dtn://local-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    decision.reason == "Bundle lifetime expired"
}

# 6. Ingress : Rejet si le nombre de sauts atteint la limite
test_maxprop_ingress_hop_limit_reached if {
    bundle := mock_data_bundle("dtn://sender/", "dtn://other-dest/", 15, 0.5)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://local-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    contains(decision.reason, "Hop limit exceeded")
}

# 7. Ingress : Ingestion d'un message Cleared List MaxProp
test_maxprop_ingress_cleared_list_message if {
    cleared := [["dtn://source-1/", 500, 3], ["dtn://source-2/", 800, 1]]
    bundle := mock_cleared_list_bundle(cleared)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://local-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "ACCEPT_CLEARED_LIST"
    decision.mutations[0].operation == "UPDATE_CLEARED_LIST"
    decision.mutations[1].operation == "PURGE_DELIVERED_BUNDLES"
}

# 8. Ingress : Ingestion d'un vecteur de probabilités MaxProp
test_maxprop_ingress_prob_vector_message if {
    bundle := {
        "primary": {
            "version": 7,
            "bundle_processing_control_flags": 0,
            "destination": constants.maxprop_broadcast_eid,
            "source": "dtn://peer-alpha/",
            "report_to": "dtn://none",
            "creation_timestamp": {"time": 1000, "sequence_number": 3},
            "lifetime": 60000,
            "processing_flags": {"deletion_report": false}
        },
        "extension_blocks": [{
            "block_type": 10,
            "hop_limit": 5,
            "hop_count": 0
        }],
        "contact_probabilities": {
            "dtn://dest-1/": 0.85,
            "dtn://dest-2/": 0.40
        }
    }
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://local-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "ACCEPT_PROB_VECTOR"
    decision.mutations[0].operation == "UPDATE_CONTACT_PROBABILITIES"
    decision.mutations[0].peer_eid == "dtn://peer-alpha/"
}

# 9. Ingress : Bundle de données régulier — calcul du coût de tri HP-MaxProp
test_maxprop_ingress_data_forward_sorting_cost if {
    # dijkstra_cost = 2.50, hop_count = 3 -> nouveau hop_count = 4
    # sorting_cost = 2.50 + (0.01 * 4) = 2.54
    bundle := mock_data_bundle("dtn://sender/", "dtn://target-dest/", 3, 2.50)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://local-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "ACCEPT_FORWARD"
    decision.mutations[0].value == 4
    decision.mutations[1].sorting_cost == 2.54
}

# 10. Contact : Livraison directe à la destination finale
test_maxprop_contact_direct_destination if {
    bundle := mock_data_bundle("dtn://sender/", "dtn://final-dest/", 2, 1.0)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://final-dest/",
            "is_broadcast": false
        },
        "node": {"local_eid": "dtn://local-node/"}
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_DIRECT"
}

# 11. Contact : Rediffusion des messages de signalisation MaxProp en broadcast
test_maxprop_contact_control_broadcast if {
    bundle := mock_cleared_list_bundle([["dtn://s/", 1, 1]])
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://broadcast/maxprop",
            "is_broadcast": true
        },
        "node": {"local_eid": "dtn://local-node/"}
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_BROADCAST"
}

# 12. Contact : Sauter un bundle déjà acquitté dans la Cleared List
test_maxprop_contact_skip_cleared if {
    bundle := mock_data_bundle("dtn://sender/", "dtn://target/", 2, 1.0)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://some-peer/",
            "is_broadcast": false
        },
        "node": {
            "local_eid": "dtn://local-node/",
            "cleared_list": ["dtn://sender/:1000:1"]
        }
    }
    decision := contact.decision with input as input
    decision.action == "SKIP_CLEARED"
}

# 13. Contact : Forward opportuniste favorable (le pair a un coût Dijkstra inférieur)
test_maxprop_contact_forward_favorable_cost if {
    # my_cost = 3.2, peer_cost = 1.8 -> peer_cost < my_cost
    bundle := mock_data_bundle("dtn://sender/", "dtn://target-dest/", 2, 3.2)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://good-relay/",
            "is_broadcast": false,
            "peer_path_costs": {"dtn://target-dest/": 1.8},
            "held_bundle_ids": []
        },
        "node": {
            "local_eid": "dtn://local-node/",
            "path_costs": {"dtn://target-dest/": 3.2}
        }
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_FAVORABLE"
    decision.mutations[0].operation == "SET_PRIORITY_COST"
}

# 14. Contact : Relais défavorable (le pair a un coût Dijkstra supérieur ou égal)
test_maxprop_contact_skip_unfavorable_cost if {
    # my_cost = 1.5, peer_cost = 4.0 -> peer_cost >= my_cost
    bundle := mock_data_bundle("dtn://sender/", "dtn://target-dest/", 2, 1.5)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://bad-relay/",
            "is_broadcast": false,
            "peer_path_costs": {"dtn://target-dest/": 4.0},
            "held_bundle_ids": []
        },
        "node": {
            "local_eid": "dtn://local-node/",
            "path_costs": {"dtn://target-dest/": 1.5}
        }
    }
    decision := contact.decision with input as input
    decision.action == "SKIP"
    contains(decision.reason, "does not offer better path cost")
}

# 15. Storage : Purge immédiate des bundles figurant dans la Cleared List
test_maxprop_storage_purge_cleared if {
    bundle := mock_data_bundle("dtn://sender/", "dtn://target-dest/", 2, 1.0)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://local-node/",
            "cleared_list": ["dtn://sender/:1000:1"]
        }
    }
    decision := storage.decision with input as input
    decision.action == "PURGE_CLEARED"
}

# 16. Storage : Éviction sélective en cas de saturation mémoire (Buffer Full)
test_maxprop_storage_evict_low_priority_buffer_full if {
    # dijkstra_cost = 6.0, hop_count = 5 -> sorting_cost = 6.0 + 0.05 = 6.05 >= seuil 5.0
    bundle := mock_data_bundle("dtn://sender/", "dtn://low-prio-dest/", 5, 6.0)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://local-node/",
            "buffer_full": true,
            "eviction_cost_threshold": 5.0
        }
    }
    decision := storage.decision with input as input
    decision.action == "EVICT_LOW_PRIORITY"
    contains(decision.reason, "Buffer congestion")
}
