# Semantic Validity

- first record should be SOA unless the last (prior to .) label in origin is "local"
- there must only be one SOA record per domain

- when adding a record check the class of the record, that fixes the class of all other records, if they differ in class return an error, zones files can only include resource records in a single class

- MX records must not specify a CNAME record by name, they must refer to an A or AAAA record
- we can only check the MX rule for records defined in the current zone, if the record referred to by the MX record exists we check it, otherwise we assume the zone containing it correctly defines it