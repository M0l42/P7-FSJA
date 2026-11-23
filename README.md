<p align="center">
   <img src="./front/src/favicon.png" width="192px" />
</p>

# MicroCRM (P7 - Développeur Full-Stack - Java et Angular - Mettez en œuvre l'intégration et le déploiement continu d'une application Full-Stack)

MicroCRM est une application de démonstration basique ayant pour être objectif de servir de socle pour le module "P7 - Développeur Full-Stack".

L'application MicroCRM est une implémentation simplifiée d'un ["CRM" (Customer Relationship Management)](https://fr.wikipedia.org/wiki/Gestion_de_la_relation_client). Les fonctionnalités sont limitées à la création, édition et la visualisations des individus liés à des organisations.

![Page d'accueil](./misc/screenshots/screenshot_1.png)
![Édition de la fiche d'un individu](./misc/screenshots/screenshot_2.png)

## Code source

### Organisation

Ce [monorepo](https://en.wikipedia.org/wiki/Monorepo) contient les 2 composantes du projet "MicroCRM":

- La partie serveur (ou "backend"), en Java SpringBoot 3;
- La partie cliente (ou "frontend"), en Angular 17.

### Démarrer avec les sources

#### Serveur

##### Dépendances

- [OpenJDK >= 17](https://openjdk.org/)

##### Procédure

1. Se positionner dans le répertoire `back` avec une invite de commande:

   ```shell
   cd back
   ```

2. Construire le JAR:

   ```shell
   # Sur Linux
   ./gradlew build

   # Sur Windows
   gradlew.bat build
   ```

3. Démarrer le service:

   ```shell
   java -jar build/libs/microcrm-0.0.1-SNAPSHOT.jar
   ```

Puis ouvrir l'URL http://localhost:8080 dans votre navigateur.

#### Client

##### Dépendances

- [NPM >= 10.2.4](https://www.npmjs.com/)

##### Procédure

1. Se positionner dans le répertoire `front` avec une invite de commande:

   ```shell
   cd front
   ```

2. (La première fois seulement) Installer les dépendances NodeJS:

   ```shell
   npm install
   ```

3. Démarrer le service de développement:

   ```shell
   npx @angular/cli serve
   ```

Puis ouvrir l'URL http://localhost:4200 dans votre navigateur.

### Exécution des tests

#### Client

**Dépendances**

- Google Chrome ou Chromium

Dans votre terminal:

```shell
cd front
CHROME_BIN=</path/to/google/chrome> npm test
```

#### Serveur

Dans votre terminal:

```shell
cd back
./gradlew test
```

### Docker

Chaque composant a son propre `Dockerfile` (`back/Dockerfile`, `front/Dockerfile`), et `docker-compose.yml` lance l'application complète.

**Dépendances :** Docker et Docker Compose v2 (`docker compose`).

#### Lancer l'application

```shell
make up      # équivaut à : docker compose up -d --build
```

- Application : http://localhost:4200
- API : http://localhost:8080

#### Commandes utiles

| Commande | Rôle |
|---|---|
| `make help` | Liste des commandes |
| `make up` / `make down` | Construire et démarrer / arrêter l'application |
| `make logs` / `make ps` | Logs des deux services / état et santé des conteneurs |
| `make smoke` | Vérifier que l'API et le front répondent |
| `make test` | Tous les tests (back + front), hors Docker |
| `make build` | Construire les deux images |

#### Configuration

| Variable | Service | Défaut | Rôle |
|---|---|---|---|
| `APP_CORS_ORIGINS` | back | `http://localhost:4200` | Origines autorisées à appeler l'API depuis un navigateur (séparées par des virgules) |
| `SITE_ADDRESS` | front | `:8080` | Adresse servie par Caddy. Un nom de domaine active le HTTPS automatique |
| `TAG` | les deux | `latest` | Version des images publiées à utiliser (`docker compose pull`) |

#### Déployer une version publiée

Les images sont publiées sur GitHub Container Registry (`ghcr.io/m0l42/microcrm-back`, `ghcr.io/m0l42/microcrm-front`) :

```shell
TAG=1.0.0 docker compose pull
TAG=1.0.0 docker compose up -d
```
