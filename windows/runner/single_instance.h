#ifndef LYCORIS_RUNNER_SINGLE_INSTANCE_H_
#define LYCORIS_RUNNER_SINGLE_INSTANCE_H_

namespace single_instance {

/// Garantiza una sola instancia de la app por PC.
///
/// Devuelve true si esta es la única instancia en curso y el proceso puede
/// seguir arrancando. Si ya había otra, la trae al frente y devuelve false
/// para que el llamador salga sin crear una segunda ventana.
///
/// El candado es por nombre de ejecutable, así que POS, Inventario y
/// Hostelería pueden estar abiertos a la vez en la misma PC sin bloquearse
/// entre sí.
bool TryAcquire();

}  // namespace single_instance

#endif  // LYCORIS_RUNNER_SINGLE_INSTANCE_H_
