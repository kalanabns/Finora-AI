import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'csv_file_reader.dart';

Future<CsvPickedFile?> pickCsvFilePlatform() async {
  final pickedFile = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['csv', 'txt'],
  );
  if (pickedFile == null) return null;

  final bytes = await pickedFile.readAsBytes();
  final content = utf8.decode(bytes, allowMalformed: true);
  return CsvPickedFile(name: pickedFile.name, content: content);
}
