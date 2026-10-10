import 'dart:async';
import 'dart:convert';

/// One Server-Sent Events frame as decoded from the wire. `id` carries the
/// server's `Last-Event-ID` token (`{requestId}:{seq}` for Farmly AI).
final class SseFrame {
  const SseFrame({this.id, this.event, this.data});

  final String? id;
  final String? event;
  final String? data;
}

/// Incremental SSE decoder (spec05 §5): a blank line ends a frame, `:` lines
/// are heartbeat comments (never semantic events), multi-line `data:` fields
/// join with newlines. Incomplete trailing input stays buffered; frames are
/// never fabricated on stream close.
final class SseDecoder {
  SseDecoder({this.onFrame});

  final void Function(SseFrame frame)? onFrame;

  final StreamController<SseFrame> _controller =
      StreamController<SseFrame>.broadcast();

  String _buffer = '';
  String? _id;
  String? _event;
  List<String> _data = const <String>[];

  Stream<SseFrame> get frames => _controller.stream;

  void addChunk(String chunk) {
    _buffer += chunk.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    int nl;
    while ((nl = _buffer.indexOf('\n')) >= 0) {
      final line = _buffer.substring(0, nl);
      _buffer = _buffer.substring(nl + 1);
      _consumeLine(line);
    }
  }

  void addBytes(List<int> bytes) =>
      addChunk(utf8.decode(bytes, allowMalformed: false));

  /// Drop a partial trailing frame and close. The server always terminates
  /// a completed frame with the blank-line boundary, so a remainder is
  /// incomplete wire data, never a semantic event.
  Future<void> close() async {
    _resetFrame();
    await _controller.close();
  }

  void _consumeLine(String line) {
    if (line.isEmpty) {
      if (_id != null || _data.isNotEmpty) {
        final frame = SseFrame(
          id: _id,
          event: _event,
          data: _data.isEmpty ? null : _data.join('\n'),
        );
        _resetFrame();
        onFrame?.call(frame);
        if (!_controller.isClosed) _controller.add(frame);
      }
      return;
    }
    if (line.startsWith(':')) return; // heartbeat comment
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'id':
        _id = value;
      case 'event':
        _event = value;
      case 'data':
        _data = <String>[..._data, value];
    }
  }

  void _resetFrame() {
    _id = null;
    _event = null;
    _data = const <String>[];
  }
}
