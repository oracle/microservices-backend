# Customer Support App

Demonstrates database Relational, JSON, Vector, and Eventing features in a progressive model using Spring Boot profiles to enable/disable certain features.

1. [Sample ticket requests](./ticket_requests.md)

## Environment variables

Before running the application, run the `user.sql` script on your database and configure the following environment variables:

```bash
APP_DB_USERNAME=<app schema username>
APP_DB_PASSWORD=<app schema password>
JDBC_URL=jdbc:oracle:thin:@<my TNS alias>?TNS_ADMIN=/path/to/wallet;
OCI_COMPARTMENT_ID=<embedding model compartment id>;
TNS_ALIAS=<tns alias>;
WALLET_DIR=</path/to/wallet>
OKAFKA_SECURITY_PROTOCOL=PLAINTEXT  # Set to PLAINTEXT for local/Docker; defaults to SSL (ADB wallet)
```

You can provision the schema with:

**Step 1 — create the app user** (run as a DBA):

```bash
export APP_DB_USERNAME=<app schema username>
export APP_DB_PASSWORD=<app schema password>
export ADMIN_DB_USERNAME=<admin username>
export ADMIN_DB_PASSWORD=<admin password>
export ADMIN_DB_CONNECT=<host:port/service>
./scripts/setup-lab-user.sh
```

**Step 2 — create the schema objects** (run as the app user):

```bash
sql ${APP_DB_USERNAME}/${APP_DB_PASSWORD}@<host:port/service> @src/test/resources/init.sql
```

`init.sql` creates the `support_ticket` table, the vector index, the `related_ticket` join table, and the `ticket_dv` JSON Relational Duality View. The app will fail with `ORA-04043` on the first request if this step is skipped.

The app now fails fast if `APP_DB_USERNAME` or `APP_DB_PASSWORD` is missing.

## App Profiles

Profiles are additive. The default is `rest`; add others to progressively unlock Oracle Database features. Activate additional profiles with:

```bash
./mvnw spring-boot:run -Dspring-boot.run.profiles=<profile1>,<profile2>
```

### rest

A basic REST controller to create and view SupportTickets.

```bash
./mvnw spring-boot:run
```

### events

Enables event-based ticket processing, replacing the basic REST controller.
- On ticket creation, an event is created and the ticket inserted into the database.
- A basic event consumer receives the ticket event and prints it to the console.

```bash
./mvnw spring-boot:run -Dspring-boot.run.profiles=events
```

### ai

Enables AI integration on ticket processing, using the `GenAIEventProcessor` class.
Each ticket processed will be embedded and linked to similar tickets using vector search.
Requires `events`.

```bash
./mvnw spring-boot:run -Dspring-boot.run.profiles=events,ai
```

### json

Enables reads through a JSON Relational Duality View (`ticket_dv`). Requires `events`.
With `ai`, tickets are also written back through the duality view in a single round-trip
(embedding + related tickets + ticket data).

The JSON read path uses `JSON_SERIALIZE` before mapping the result. Oracle's
`com.oracle.spring.json.jsonb.JSONBRowMapper` is usable for JSON without vector
values, but its direct binary-JSON parser fails with `ORA-26318` when it reads
this view's vector embedding. Serialization exposes the vector as an ordinary
JSON number array that the ticket mapper can read. Writes still use Oracle JSONB
and binary JSON (OSON); this workaround adds a text conversion only on reads.

```bash
# Minimum — reads via ticket_dv, writes via direct SQL
./mvnw spring-boot:run -Dspring-boot.run.profiles=events,json

# Full round-trip through the duality view (requires OCI credentials)
./mvnw spring-boot:run -Dspring-boot.run.profiles=events,ai,json
```

## API

The REST API is available in all profiles.

#### Create a ticket

```bash
curl -X POST -H 'Content-Type: application/json' \
  "http://localhost:8080/tickets" \
  -d '{"title": "My ticket", "description": "Need help with XYZ!"}'
```

#### Retrieve a ticket

```bash
curl -X GET "http://localhost:8080/tickets/{id}"
```

#### Retrieve all tickets

```bash
curl -X GET "http://localhost:8080/tickets"
```

## ORDS

ORDS (Oracle REST Data Services) must be installed and configured separately — it is not included in the `gvenzl/oracle-free` Docker image. It is pre-installed on OCI Autonomous Database. Run `src/test/resources/ords.sql` as the app user to enable the REST-enabled schema and view with authorization required.

For this lab, the ORDS AutoREST endpoint is accessed with database Basic authentication using the application schema credentials. Use HTTPS when passing database credentials. If you run standalone ORDS, make sure database/schema authentication is enabled for the ORDS pool before testing these `curl` commands.

When the ORDS schema and view are enabled, we can fetch ticket data using the ORDS REST API:

Unauthenticated requests should be rejected:

```bash
curl -i -X GET $ORDS_URL/support/ticket/
```

Authenticated requests use the application database credentials:

```bash
curl -X GET $ORDS_URL/support/ticket/ \
  -u "$APP_DB_USERNAME:$APP_DB_PASSWORD"
```

```bash
curl -X GET $ORDS_URL/support/ticket/ \
  -H "Content-Type: application/json"  \
  -u "$APP_DB_USERNAME:$APP_DB_PASSWORD"
```

## Cleanup between stages

The app includes a "Delete All" API that clears all app data, and can be run between showcase stages to clean-up data.

```bash
curl -X DELETE "http://localhost:8080/tickets"
```
