# FleetSec Security

Prueba técnica para el rol de Ingeniero de Ciberseguridad.

## Descripción

Este proyecto implementa un laboratorio de seguridad para FleetSec S.A.S., orientado a integrar controles de seguridad dentro del ciclo de desarrollo mediante prácticas DevSecOps.

## Tecnologías utilizadas

- Python
- FastAPI
- Docker
- GitHub Actions
- Semgrep
- Trivy
- Gitleaks
- OWASP ZAP
- Terraform
- Checkov

## Ejecución local

Crear entorno virtual:

```powershell
python -m venv .venv

Activar:

.\.venv\Scripts\Activate.ps1

Instalar dependencias:

pip install -r requirements.txt
pip install pytest

Ejecutar pruebas:

python -m pytest

Ejecutar aplicación:

uvicorn app.main:app --reload

Health check:

http://127.0.0.1:8000/health

OpenAPI:

http://127.0.0.1:8000/openapi.json
Pipeline DevSecOps

El pipeline principal se encuentra en:

.github/workflows/security-pipeline.yml

Actualmente integra:

Pruebas automatizadas con Pytest.
Gitleaks para detección de secretos.
Semgrep para SAST.
Trivy para SCA.
Generación de SBOM CycloneDX.
Análisis de imágenes Docker con Trivy.
Terraform Validate.
Checkov.
OWASP ZAP para DAST autenticado.
Resultado del pipeline

Se realizó una ejecución exitosa del pipeline en GitHub Actions con una duración de:

3 min 27 s

El pipeline tiene configurado un límite máximo de:

timeout-minutes: 15
Optimización aplicada

Se implementó caché de dependencias Python:

cache: "pip"
cache-dependency-path: requirements.txt

También se configuró el checkout con historial completo para permitir el análisis correcto del historial Git por Gitleaks:

fetch-depth: 0
DAST

OWASP ZAP se ejecuta mediante Automation Framework con autenticación Bearer JWT.

Archivo de configuración:

security/zap/zap.yaml

Resultado de cobertura:

OpenAPI endpoints: 15
Covered endpoints: 15
Coverage: 100.00%
Minimum required: 80.00%

Resultado del gate:

HIGH/CRITICAL: 0
MEDIUM: 1
PASS

La alerta MEDIUM corresponde a HTTP Only Site en el entorno de staging.

Secret Scanning

Gitleaks está integrado en:

pre-commit local
pipeline de GitHub Actions

Hook:

.githooks/pre-commit

Configuración local:

git config core.hooksPath .githooks

Prueba local realizada:

no leaks found
Gitleaks no detectó secretos.
Break-glass

Archivos:

.github/CODEOWNERS
.github/workflows/break-glass.yml

El mecanismo implementado contempla:

etiqueta break-glass
generación de Issue CRITICAL
registro del Pull Request y ejecución del workflow
validación de dos aprobadores distintos

El repositorio actualmente tiene configurado:

* @karolina-dev

La validación de dos aprobadores distintos requiere un segundo colaborador real en GitHub.

VAPT

La aplicación contiene endpoints de laboratorio para demostrar vulnerabilidades y sus respectivas remediaciones.

Los tipos trabajados son:

SQL Injection
JWT alg:none
SSRF
XXE
Mass Assignment
Path Traversal
Missing Rate Limiting
Logging de PII
IDOR
Hardcoded Credentials

El reporte VAPT será incluido en el repositorio como parte de la entrega final.

Estado de los entregables
Bloque 1 — Pipeline DevSecOps

Estado: implementado y validado

Bloque 2 — VAPT y Remediación

Estado: implementado y en proceso de documentación final

Bloque 3 — Hardening AWS Terraform

Estado: en desarrollo

Bloque 4 — Detección y Respuesta a Incidentes

Estado: pendiente

ADRs
ADR-001 — GitHub Actions

Se utiliza GitHub Actions como plataforma para ejecutar el pipeline DevSecOps.

ADR-002 — OWASP ZAP

Se utiliza OWASP ZAP Automation Framework para realizar DAST autenticado.

ADR-003 — Gitleaks

Se utiliza Gitleaks tanto en desarrollo local como en CI para detección de secretos.

Reporte de IA

La IA fue utilizada como apoyo para:

estructuración del pipeline
generación y revisión de archivos YAML
creación de scripts auxiliares
análisis de errores
documentación técnica

Durante el desarrollo se detectaron errores generados inicialmente con apoyo de IA, entre ellos problemas en la implementación del pre-commit de Gitleaks y en la configuración del historial Git utilizado por Gitleaks en GitHub Actions.

Estos problemas fueron identificados mediante pruebas reales y posteriormente corregidos.

Desafíos
Integración de OWASP ZAP con autenticación JWT.
Validación de cobertura OpenAPI.
Revisión de falsos positivos de DAST.
Integración de Gitleaks en Windows y GitHub Actions.
Validación de Terraform y Checkov.
Próximos pasos
Finalizar el hardening AWS Terraform.
Completar la tabla CIS AWS / ISO 27001 / Ley 1581.
Completar los IOCs y Threat Intelligence.
Crear las reglas Sigma.
Completar el playbook de respuesta a incidentes.
Completar el mapeo MITRE ATT&CK.
Finalizar la documentación VAPT.
Agregar el enlace del video de sustentación.
Configurar el segundo colaborador para las dos aprobaciones de Break-glass.

Video de sustentación

Pendiente de agregar enlace de YouTube.

Licencia

Uso exclusivo para la prueba técnica de FleetSec.