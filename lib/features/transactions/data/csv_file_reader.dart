import 'csv_file_reader_stub.dart'
    if (dart.library.js_interop) 'csv_file_reader_web.dart'
    if (dart.library.io) 'csv_file_reader_io.dart';

class CsvPickedFile {
  CsvPickedFile({
    required this.name,
    required String content,
  }) : content = content.startsWith('\uFEFF') ? content.substring(1) : content;

  final String name;
  final String content;
}

Future<CsvPickedFile?> pickCsvFile() => pickCsvFilePlatform();
