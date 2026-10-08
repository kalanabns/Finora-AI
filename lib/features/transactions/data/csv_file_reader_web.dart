import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'csv_file_reader.dart';

Future<CsvPickedFile?> pickCsvFilePlatform() async {
  final completer = Completer<CsvPickedFile?>();

  final input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = '.csv,.txt,text/csv,text/plain';
  input.style.display = 'none';

  // Attach to DOM so desktop browsers maintain active connection during dialog
  web.document.body?.appendChild(input);

  void cleanup() {
    input.remove();
  }

  input.addEventListener(
    'change',
    ((web.Event event) {
      final files = input.files;
      if (files == null || files.length == 0) {
        cleanup();
        if (!completer.isCompleted) completer.complete(null);
        return;
      }

      final file = files.item(0)!;
      final reader = web.FileReader();

      reader.addEventListener(
        'loadend',
        ((web.Event _) {
          cleanup();
          if (!completer.isCompleted) {
            final result = reader.result;
            final content = (result as JSString?)?.toDart ?? '';
            completer.complete(CsvPickedFile(name: file.name, content: content));
          }
        }).toJS,
      );

      reader.addEventListener(
        'error',
        ((web.Event _) {
          cleanup();
          if (!completer.isCompleted) completer.complete(null);
        }).toJS,
      );

      reader.readAsText(file);
    }).toJS,
  );

  input.addEventListener(
    'cancel',
    ((web.Event _) {
      cleanup();
      if (!completer.isCompleted) completer.complete(null);
    }).toJS,
  );

  input.click();

  return completer.future;
}
