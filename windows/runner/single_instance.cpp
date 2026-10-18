#include "single_instance.h"

#include <windows.h>

#include <string>

namespace {

/// Nombre del ejecutable actual, sin ruta (p. ej. "LycorisPOS.exe").
std::wstring ExeBaseName() {
  wchar_t path[MAX_PATH]{};
  ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring name(path);
  const size_t slash = name.find_last_of(L"\\/");
  if (slash != std::wstring::npos) {
    name = name.substr(slash + 1);
  }
  return name;
}

/// Candado con nombre, acotado a la sesión de Windows y al binario: una
/// instancia por app y por PC. POS, Inventario y Hostelería no se bloquean
/// entre sí porque cada uno tiene su propio ejecutable
/// (LYCORIS_BINARY_NAME en .github/workflows/release.yml).
std::wstring MutexNameFor(const std::wstring& exe_base_name) {
  return L"Local\\LycorisSingleInstance-" + exe_base_name;
}

/// Título compartido por las ventanas que crea el runner
/// (ver main.cpp: `window.Create(L"control_entradas_salidas", ...)`).
constexpr const wchar_t kWindowTitle[] = L"control_entradas_salidas";

/// Nombre del ejecutable (sin ruta) del proceso `pid`.
std::wstring ExeBaseNameOfProcess(DWORD pid) {
  HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) {
    return L"";
  }
  wchar_t buffer[MAX_PATH]{};
  DWORD size = MAX_PATH;
  std::wstring name;
  if (::QueryFullProcessImageNameW(process, 0, buffer, &size)) {
    name = buffer;
    const size_t slash = name.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
      name = name.substr(slash + 1);
    }
  }
  ::CloseHandle(process);
  return name;
}

/// Busca la ventana de la instancia que ya está corriendo y la trae al
/// frente. El título solo no basta (podrían correr POS e Inventario a la
/// vez, con el mismo título): se confirma además el ejecutable del proceso
/// dueño de la ventana.
void FocusExistingInstance(const std::wstring& self_exe) {
  const DWORD self_pid = ::GetCurrentProcessId();
  HWND hwnd = nullptr;
  while ((hwnd = ::FindWindowExW(nullptr, hwnd, nullptr, kWindowTitle)) !=
         nullptr) {
    DWORD pid = 0;
    ::GetWindowThreadProcessId(hwnd, &pid);
    if (pid == 0 || pid == self_pid) {
      continue;
    }
    if (ExeBaseNameOfProcess(pid) != self_exe) {
      continue;
    }
    ::ShowWindow(hwnd, SW_RESTORE);
    ::SetForegroundWindow(hwnd);
    return;
  }
}

}  // namespace

namespace single_instance {

bool TryAcquire() {
  const std::wstring exe = ExeBaseName();
  // El mutex se libera solo al morir el proceso (incluso si crashea), así
  // que nunca queda un candado huérfano que bloquee la app.
  HANDLE mutex = ::CreateMutexW(nullptr, TRUE, MutexNameFor(exe).c_str());
  if (mutex == nullptr) {
    // Sin candado no hay forma de garantizar una sola instancia: mejor
    // dejar entrar a la app que bloquear el trabajo en caja.
    return true;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Ya hay otra instancia: no se abre una segunda ventana con una sesión
    // en memoria propia (que quedaría como fantasma tras cerrar el turno);
    // se enfoca la que ya existe y se sale.
    FocusExistingInstance(exe);
    ::CloseHandle(mutex);
    return false;
  }
  return true;
}

}  // namespace single_instance
