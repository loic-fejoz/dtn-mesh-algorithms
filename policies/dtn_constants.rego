package dtn.constants

# Offset entre l'époque Unix (1970-01-01T00:00:00Z) et l'époque DTN (2000-01-01T00:00:00Z) en millisecondes
dtn_epoch_offset_ms := 946684800000

# Types de blocs BPv7 (RFC 9171)
block_type_payload := 1
block_type_previous_node := 6
block_type_bundle_age := 7
block_type_hop_count := 10

# Codes de raison de suppression de bundle (RFC 9171 Section 9.7)
reason_lifetime_expired := 1
reason_forwarded_unidirectional := 2
reason_transmission_canceled := 3
reason_depleted_storage := 4
reason_destination_unavailable := 5
reason_no_known_route := 6
reason_no_timely_contact := 7
reason_block_unparseable := 8
reason_hop_limit_exceeded := 9
reason_traffic_pared := 10
reason_block_unsupported := 11
reason_missing_critical_block := 12

# Flags de contrôle de traitement de bundle (RFC 9171 Section 4.2.3)
# Bit 14 : Requête de rapport d'état en cas de suppression
flag_report_deletion := 16384
