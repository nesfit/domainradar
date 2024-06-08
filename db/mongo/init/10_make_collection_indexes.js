// @ts-ignore
db = db.getSiblingDB('domainradar');

db.dn_data.createIndex({ "_id.domainName": 1 }, { unique: false });
db.ip_data.createIndex({ "_id.domainName": 1 }, { unique: false });
db.filtered_domains.createIndex({ "_id.domainName": 1 }, { unique: false });

db.classification_results.createIndex({ "domain_name": 1 }, { unique: false });
