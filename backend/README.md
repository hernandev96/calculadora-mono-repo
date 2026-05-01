# API Calculadora - Backend (FastAPI)

## Stack
- **Runtime**: Python 3.12
- **Framework**: FastAPI + Uvicorn
- **Contenerización**: Docker

## Endpoints

| Método | Ruta              | Descripción                        |
|--------|-------------------|------------------------------------|
| GET    | `/api/health`     | Health check (liveness/readiness)  |
| GET    | `/api/sumar`      | Suma `?a=2&b=3`                   |
| GET    | `/api/restar`     | Resta `?a=10&b=4`                 |
| POST   | `/api/multiplicar`| Multiplica `{"a": 3, "b": 4}`     |
| POST   | `/api/dividir`    | Divide `{"a": 10, "b": 2}`        |

## Variables de entorno

| Variable          | dev     | staging                  | prod                    |
|-------------------|---------|--------------------------|-------------------------|
| `ENVIRONMENT`     | `dev`   | `staging`                | `prod`                  |
| `ALLOWED_ORIGINS` | `*`     | `https://stg.miapp.com`  | `https://miapp.com`     |
| `LOG_LEVEL`       | `debug` | `info`                   | `warn`                  |

## Desarrollo local

```bash
# Sin Docker
pip install -r requirements.txt
uvicorn main:app --reload

# Con Docker (desde la raiz del monorepo)
docker compose up backend --build

# Probar health check
curl http://localhost:8000/api/health
```

## Documentación interactiva
- Swagger UI: http://localhost:8000/api/docs
- ReDoc: http://localhost:8000/api/redoc

## Observabilidad

Los logs se emiten en formato JSON estructurado a stdout (compatible con Kubernetes).
Dos flujos separados:
- **Técnico**: latencia, status, errores
- **Auditoría**: quién hizo qué operación

En Kubernetes, Promtail/Fluentd los recolecta automáticamente desde stdout del pod.

# TestJL back
