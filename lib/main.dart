import 'dart:async';

import 'package:clipboard/clipboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart' as csb;
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:chess/chess.dart' as chess_lib;
import 'package:window_manager/window_manager.dart';
import 'package:logger/logger.dart';

import 'package:stockfish_for_flutter/stockfish.dart';

class MyLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return true;
  }
}

void main() {
  runApp(const MaterialApp(
    home: MyApp(),
  ));
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WindowListener {
  late Stockfish _stockfish;
  final _fenController = TextEditingController(
      text: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
  late StreamSubscription _stockfishOutputSubsciption;
  var _timeMs = 1000.0;
  var _nextMove = '';
  var _stockfishOutputText = '';
  final _logger = Logger(filter: MyLogFilter());
  String arrow_start = "";
  String arrow_finish = "";

  @override
  void initState() {
    windowManager.addListener(this);
    _chessController.addListener(_movehappen);
    //_overrideDefaultCloseHandler();
    _doStartStockfish();
    super.initState();
  }

  // Future<void> _overrideDefaultCloseHandler() async {
  //   await windowManager.setPreventClose(true);
  //   setState(() {});
  // }

  @override
  void dispose() {
    _chessController.dispose();
    _stopStockfish();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    _stopStockfish();
    await Future.delayed(const Duration(milliseconds: 200));
    await windowManager.destroy();
  }

  void _readStockfishOutput(String output) {
    // At least now, stockfish is ready : update UI.
    _stockfishOutputText = "$output\n";
    //print(output);
    if (output.contains('currmove')) {
      final parts = output.split(' ');
      setState(() {
        _nextMove = parts[4];
      });
    } else if (output.contains('pv')) {
      final parts = output.split('pv ');
      //print(parts[2].substring(0, 4));
      setState(() {
        _nextMove = parts[2].substring(0, 4);
      });
    } else {
      _nextMove = "";
    }
  }

  void _movehappen() {
    if (_fenController.text != _chessController.getFen()) {
      _fenController.text = _chessController.getFen();
      if (_stockfish.state.value == StockfishState.ready) {
        _computeNextMove();
      }
    }
  }

  void _pasteFen() {
    FlutterClipboard.paste().then((value) {
      setState(() {
        _fenController.text = value;
      });
    });
  }

  void _updateThinkingTime(double newValue) {
    setState(() {
      _timeMs = newValue;
    });
  }

  bool _validPosition() {
    final chess = chess_lib.Chess();
    return chess.load(_fenController.text.trim());
  }

  void _computeNextMove() {
    if (!_validPosition()) {
      final message = "Illegal position: '${_fenController.text.trim()}' !\n";
      _stockfishOutputText = message;
      return;
    }

    _stockfishOutputText = '';

    _stockfish.stdin = 'stop';
    _stockfish.stdin = 'position fen ${_fenController.text.trim()}';
    _stockfish.stdin = 'go infinite';
  }

  void _stopStockfish() async {
    if (_stockfish.state.value == StockfishState.disposed ||
        _stockfish.state.value == StockfishState.error) {
      return;
    }
    _stockfishOutputSubsciption.cancel();
    _stockfish.stdin = 'stop';
    _stockfish.stdin = 'quit';
    _stockfish.dispose();
    await Future.delayed(const Duration(milliseconds: 200));
    setState(() {});
  }

  void _doStartStockfish() async {
    _stockfish = Stockfish();
    _stockfishOutputSubsciption =
        _stockfish.stdout.listen(_readStockfishOutput);
    setState(() {
      _stockfishOutputText = '';
    });
    await Future.delayed(const Duration(milliseconds: 1100));
    _stockfish.stdin = 'uci';
    await Future.delayed(const Duration(milliseconds: 3000));
    _stockfish.stdin = 'isready';
  }

  void _startStockfishIfNecessary() {
    setState(() {
      if (_stockfish.state.value == StockfishState.ready ||
          _stockfish.state.value == StockfishState.starting) {
        return;
      }
      _doStartStockfish();
    });
  }

  Icon _getStockfishStatusIcon() {
    Color color = Colors.black;
    switch (_stockfish.state.value) {
      case StockfishState.ready:
        color = Colors.green;
        break;
      case StockfishState.disposed:
      case StockfishState.error:
        color = Colors.red;
        break;
      case StockfishState.starting:
        color = Colors.orange;
    }
    return Icon(MdiIcons.circle, color: color);
  }

  csb.ChessBoardController _chessController = csb.ChessBoardController();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Stockfish Chess Engine example"),
        ),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TextField(
                controller: _fenController,
                decoration: const InputDecoration(
                  hintText: 'Position FEN value',
                  border: OutlineInputBorder(),
                ),
              ),
              ElevatedButton(
                onPressed: _pasteFen,
                child: const Text('Paste FEN'),
              ),
              ElevatedButton(
                onPressed: _computeNextMove,
                child: const Text('Search next move'),
              ),
              Text(
                  'Best move: ${_nextMove != "" ? _nextMove.substring(0, 2) : ""},${_nextMove != "" ? _nextMove.substring(2, 4) : ""}'),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _getStockfishStatusIcon(),
                  ElevatedButton(
                    onPressed: _startStockfishIfNecessary,
                    child: const Text('Start Stockfish'),
                  ),
                  ElevatedButton(
                    onPressed: _stopStockfish,
                    child: const Text('Stop Stockfish'),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: csb.ChessBoard(
                    controller: _chessController,
                    boardColor: csb.BoardColor.orange,
                    arrows: _nextMove != ""
                        ? ([
                            csb.BoardArrow(
                              from: _nextMove.substring(0, 2),
                              to: _nextMove.substring(2, 4),
                              color: Colors.green.withOpacity(0.5),
                            ),
                          ])
                        : [],
                    boardOrientation: csb.PlayerColor.white,
                  ),
                ),
              ),
              // Padding(
              //   padding: const EdgeInsets.all(8.0),
              //   child: Container(
              //     width: 850.0,
              //     height: 300.0,
              //     decoration: BoxDecoration(
              //       border: Border.all(
              //         width: 2.0,
              //       ),
              //       borderRadius: const BorderRadius.all(
              //         Radius.circular(8.0),
              //       ),
              //     ),
              //     child: SingleChildScrollView(
              //       child: Text(
              //         _stockfishOutputText,
              //       ),
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}
