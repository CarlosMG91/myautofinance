# Verificación MA-TSK-234 · Guía de usuario Windows

Fecha: 2026-10-18. Guía: [guia-usuario-windows.md](guia-usuario-windows.md).

## Revisión realizada

- Contrastadas las instrucciones con el contrato T01 y los documentos de implementación/verificación T05/T06: destino estable, versión numérica, reparación, downgrade, adopción explícita, conservación de identidad en actualización y limpieza local de credencial propia en uninstall.
- Contrastadas las rutas de datos con el contrato: binarios en `%LOCALAPPDATA%\Programs\Autofinance`; soporte en Known Folder `RoamingAppData\com.carlosmg91\Autofinance` (normalmente `%APPDATA%\com.carlosmg91\Autofinance`). Se explican SQLite/sidecars, copias, diarios, Drive y Credential Manager sin recomendar manipulación manual.
- La guía deriva recuperación de esquema a EP-004 y de copias/diarios a EP-006. EP-027 queda como opción futura y no como requisito.
- `git diff --check -- docs/ep-028/guia-usuario-windows.md docs/ep-028/verificacion-guia.md`: correcto.

## Pendiente de T08

No se dispone aquí de paquete real de producción ni de perfil/VM desechable para la matriz nativa. No se afirma que el procedimiento se haya ejecutado sobre Windows limpio ni que se hayan probado allí espacios/acentos, offline, sesión preservada, recuperación o uninstall. Según [verificación T05](verificacion-instalador.md) y [verificación T06](verificacion-generacion.md), el paquete real no está generado y la aceptación T08 sigue pendiente. Los resultados de fixtures/contratos no sustituyen esa prueba. T08 debe validar las rutas con espacios y acentos y los casos del contrato en Windows 10/11 x64 desechable antes de presentar la instalación como aceptada.

La guía y esta nota son la entrega documental de T07; no se modificó el mockup ni se presentó aceptación visual.
