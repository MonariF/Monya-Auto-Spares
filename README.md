# Monya Auto Spares Management System

A mobile-first spare parts shop management system for Monya Auto Spares.

## Agreed project requirements

- **Currency:** Kenyan Shillings (KES)
- **Shop locations:** One shop
- **Employee access:** Individual employee access
- **Offline operation:** Required
- **Profit reporting:** Daily profit reporting
- **Core shop operations:** Inventory, sales and purchases

The application is intended to support day-to-day spare parts shop operations, with reliable record keeping and a workflow suitable for use on a mobile phone.

## Development status

This repository is the source-control home for the project. The initial commit records the agreed requirements. Application source files and the database implementation have **not yet been added**.

## Planned implementation areas

1. Product and inventory records
2. Purchase and stock-in records
3. Sales and stock-out records
4. Individual employee access and activity records
5. Offline data capture and synchronisation design
6. Daily profit and transaction reports
7. Data backup, validation and recovery procedures

## Important implementation principles

- Preserve existing shop records when adding or changing features.
- Do not expose database passwords, API keys, employee credentials or other secrets in this public repository.
- Test stock and financial calculations before using the system for live shop transactions.
- Make the offline workflow explicit about which records are saved locally and which have synchronised to the central database.

## Technology and deployment

The final database, hosting and synchronisation configuration will be documented after the implementation choices are confirmed. Do not place live credentials in source files. Use environment variables or the hosting platform's secret-management settings.

## Project owner

Monya Auto Spares
