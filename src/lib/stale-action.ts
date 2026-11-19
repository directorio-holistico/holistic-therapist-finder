// After a deploy, a page that was already open in someone's browser is "old": the server no longer recognizes its Server Actions.
// Next.js then throws an UnrecognizedActionError on the client. This turns that error into a normal message instead of a blank or broken screen.
// Después de un deploy, una página que ya estaba abierta en el navegador queda "vieja": el servidor ya no reconoce sus Server Actions.
// Next.js entonces lanza un UnrecognizedActionError en el cliente. Esto convierte ese error en un mensaje normal, en vez de una pantalla en blanco o rota.

export const STALE_MESSAGE =
  "El sitio se actualizó mientras completabas el formulario y esta pantalla quedó vieja, por eso no se pudo guardar. Tocá «Recargar la página» y volvé a cargar tus datos. Lo que ya habías guardado como borrador no se pierde.";

// Runs the action. If it fails only because the page is out of date, it returns the given result; any other error is thrown again as is.
// Ejecuta la acción. Si falla solo porque la página está desactualizada, devuelve el resultado indicado; cualquier otro error se vuelve a lanzar tal cual.
export async function runGuarded<T>(run: () => Promise<T>, isStale: (error: unknown) => boolean, onStale: T): Promise<T> {
  try {
    return await run();
  } catch (error) {
    if (isStale(error)) return onStale;
    throw error;
  }
}
