import '../../../../core/models/hosteleria_models.dart';

/// Datos mutables de un huésped mientras se edita en `HuespedForm`.
///
/// Se usa tanto para el titular como para cada acompañante; al guardar se
/// envían al repositorio mediante [HosteleriaRepository.saveHuesped].
class HuespedDraft {
  HuespedDraft();

  HuespedDraft.desde(HostelHuesped h)
      : nombre = h.nombre,
        apellido = h.apellido ?? '',
        tipoDocumento = h.tipoDocumento ?? DocumentoTipo.cedula,
        numeroDocumento = h.documento ?? '',
        fechaNacimiento = h.fechaNacimiento,
        estadoCivil = h.estadoCivil,
        nacionalidad = h.nacionalidad ?? '',
        profesion = h.profesion ?? '',
        procedencia = h.procedencia ?? '',
        destino = h.destino ?? '',
        telefono = h.telefono ?? '',
        correo = h.correo ?? '',
        notas = h.notas ?? '',
        huespedId = h.id;

  String nombre = '';
  String apellido = '';
  String tipoDocumento = DocumentoTipo.cedula;
  String numeroDocumento = '';
  DateTime? fechaNacimiento;
  String? estadoCivil;
  String nacionalidad = '';
  String profesion = '';
  String procedencia = '';
  String destino = '';
  String telefono = '';
  String correo = '';
  String notas = '';

  /// Id del huésped ya guardado (acompañantes existentes / titular de reserva).
  int? huespedId;

  bool get valido => nombre.trim().isNotEmpty && apellido.trim().isNotEmpty;

  /// Copia editable e independiente (para diálogos que pueden cancelarse).
  HuespedDraft copia() => HuespedDraft()
    ..nombre = nombre
    ..apellido = apellido
    ..tipoDocumento = tipoDocumento
    ..numeroDocumento = numeroDocumento
    ..fechaNacimiento = fechaNacimiento
    ..estadoCivil = estadoCivil
    ..nacionalidad = nacionalidad
    ..profesion = profesion
    ..procedencia = procedencia
    ..destino = destino
    ..telefono = telefono
    ..correo = correo
    ..notas = notas
    ..huespedId = huespedId;

  String? get errorValidacion {
    if (nombre.trim().isEmpty) return 'Ingrese el nombre.';
    if (apellido.trim().isEmpty) return 'Ingrese el apellido.';
    return null;
  }

  String get etiqueta {
    final n = '$nombre $apellido'.trim();
    return n.isEmpty ? 'Nuevo huésped' : n;
  }
}
