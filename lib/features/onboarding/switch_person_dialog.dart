import 'package:flutter/material.dart';

/// Texto de confirmación al pasar el celular de una persona a otra.
String switchPersonMessage({required String fromName, String? toName}) {
  final from = fromName.trim().isEmpty ? 'la persona anterior' : fromName.trim();
  final to = toName?.trim() ?? '';
  if (to.isEmpty) {
    return 'Este celular pasará a otra persona y saldrá $from de este aparato.';
  }
  return 'Este celular pasará a ser de $to y saldrá $from de este aparato.';
}

/// true si confirma el cambio de persona en este celular.
Future<bool> confirmSwitchPerson(
  BuildContext context, {
  required String fromName,
  String? toName,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        toName == null || toName.trim().isEmpty
            ? 'Cambiar de persona'
            : 'Cambiar a $toName',
      ),
      content: Text(switchPersonMessage(fromName: fromName, toName: toName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Seguir como $fromName'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Cambiar en este celular'),
        ),
      ],
    ),
  );
  return ok == true;
}
