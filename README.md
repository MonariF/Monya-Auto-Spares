# Monya Auto Spares — Phase 1 Foundation

A mobile-first Progressive Web App (PWA) shell for the Monya Auto Spares shop-management project.

## Confirmed requirements

- **Currency:** Kenyan Shillings (KES)
- **Shop locations:** One shop
- **Employee access:** Individual employee accounts
- **Offline operation:** The app shell can be cached for repeat/offline opening. Offline sales queues and conflict-safe synchronisation are later implementation work.
- **Daily reporting:** Daily sales and gross-profit reporting are planned.
- **Access roles:** Owner/administrator and employee, with protected inventory fields reserved for the owner.

## Files in this repository

- `index.html` — dashboard and Phase 1 interface
- `styles.css` — responsive mobile-first styling
- `app.js` — date, currency display, connection indicator and service-worker registration
- `manifest.webmanifest` — PWA metadata
- `service-worker.js` — caches the application shell for repeat/offline opening
- `.gitignore` — excludes common local secrets, databases, backups and generated files

## Preview locally

Service workers require localhost or HTTPS. From the project folder, run:

```bash
python -m http.server 8000
```

Then open `http://localhost:8000`.

## Current implementation boundary

This is a **Phase 1 interface foundation**, not a live multi-user inventory system. The dashboard figures are placeholders. The current frontend does not yet provide live database connectivity, login, stock editing, sales recording, Excel import/export, daily closing or offline sales synchronisation.

The README supplied with the project describes a planned Supabase schema at `supabase/schema.sql`, but that SQL file was **not included in the uploaded source files** and is not present in this repository yet. Do not run a database setup step until the actual schema file has been added and reviewed.

## Planned database and production work

1. Add and review the Supabase PostgreSQL schema, indexes and row-level security policies.
2. Configure Supabase authentication and securely assign owner and individual employee roles.
3. Connect the frontend using only the Supabase project URL and publishable/anon key. Never put the `service_role` key in browser code.
4. Implement a transactional database function (RPC) that atomically validates stock, records sales and sale lines, deducts stock, snapshots buying/selling prices and records an audit event.
5. Implement offline sales with unique client-generated transaction IDs and conflict reconciliation to prevent duplicate posting or overselling.
6. Add inventory import/export, daily sales and gross-profit reporting, backups, monitoring and automated tests.
7. Test row-level security with separate owner and employee accounts, then deploy only over HTTPS.

## Security notes

- Do not commit Supabase secrets, service-role keys, passwords, employee credentials or private shop data.
- Use hosting-platform secret settings or environment variables for private configuration.
- Test all stock and financial calculations before enabling live transactions.

## Project owner

Monya Auto Spares
