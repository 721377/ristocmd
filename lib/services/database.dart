import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DatabaseHelper {
  static const _databaseName = "RestaurantDB.db";
  static const _databaseVersion =
      14; // Updated to match the highest version in onUpgrade

  // Sala table
  static const salaTable = 'sala';
  static const salaId = 'id';
  static const salaDes = 'des';
  static const salaListino = 'listino';

  // Tavolo table
  static const tavoloTable = 'tavolo';
  static const tavoloId = 'id';
  static const tavoloIdSala = 'id_sala';
  static const tavoloDes = 'des';
  static const tavoloModBanco = 'mod_banco';
  static const tavoloCoperti = 'coperti';
  static const tavoloContiAperti = 'conti_aperti';
  static const tavoloNumOrdine = 'num_ordine';
  static const tavoloStatoAvanzamento = 'stato_avanzamento';
  static const tavoloDesSala = 'des_sala';

  // Singleton pattern
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Central table definitions
  final Map<String, String> tables = {
    'impostazioni_palm': '''
  CREATE TABLE impostazioni_palm (
    wsport INTEGER,
    chiusura_palmare INTEGER,
    avanzamento_sequenza INTEGER,
    avanzamento_palmare INTEGER,
    pv INTEGER,
    abilita_satispay INTEGER,
    listino_palmari INTEGER,
    licenze_palmari INTEGER,
    ristocomande_ver TEXT,
    copertoPalm INTEGER
  )
''',
    'operatore': '''
  CREATE TABLE operatore (
    id INTEGER PRIMARY KEY,
    nome TEXT,
    cognome TEXT,
    username TEXT,
    password TEXT,
    email TEXT,
    vis_lis TEXT,
    vis_cosu TEXT,
    tipo_permesso INTEGER,
    usa_terminale INTEGER,
    remember_token TEXT,
    chiedere_password INTEGER
  )
''',
    'sala': '''
      CREATE TABLE sala (
        id INTEGER PRIMARY KEY,
        des TEXT NOT NULL,
        listino INTEGER NOT NULL
      )
    ''',
    'tavolo': '''
      CREATE TABLE tavolo (
        id INTEGER PRIMARY KEY,
        id_sala INTEGER NOT NULL,
        des TEXT NOT NULL,
        pos_left INTEGER,
        pos_top INTEGER,
        mod_banco INTEGER NOT NULL,
        asporto INTEGER,
        coperti INTEGER NOT NULL,
        conti_aperti INTEGER NOT NULL,
        num_ordine INTEGER,
        is_locked INTEGER DEFAULT 0,
        is_occupied INTEGER DEFAULT 0,
        is_pending INTEGER DEFAULT 0,
        stato_avanzamento INTEGER,
        des_sala TEXT,
        FOREIGN KEY (id_sala) REFERENCES sala (id)
      )
    ''',
    'orders': '''
      CREATE TABLE orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mov_cod TEXT NOT NULL,
    mov_descr TEXT NOT NULL,
    mov_prz REAL,
    mov_qta INTEGER,
    mov_aliiva TEXT,
    tavolo INTEGER,
    sala INTEGER,
    is_coperto INTEGER DEFAULT 0,
    timer_start DATETIME,
    timer_stop DATETIME,
    variantiDes TEXT,
    variantiPrz REAL,
    variantiDesMeno TEXT,
    variantiPrzMeno REAL,
    seq INTEGER,
    pagato INTEGER,
    created_at DATETIME,
    updated_at DATETIME
  );

    ''',
    'gruppi': '''
      CREATE TABLE gruppi (
        id INTEGER PRIMARY KEY,
        des TEXT,
        menu_pranzo INTEGER,
        menu_cena INTEGER
      )
    ''',
    'articoli': '''
      CREATE TABLE articoli (
        id INTEGER PRIMARY KEY,
        cod TEXT,
        des TEXT,
        qta INTEGER,
        prezzo REAL,
        id_cat INTEGER,
        cat_des TEXT,
        id_ag INTEGER,
        svincolo_sequenza INTEGER
      )
    ''',
    'varianti': '''
  CREATE TABLE varianti (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cod TEXT NOT NULL,
    des TEXT,
    id_cat INTEGER NOT NULL,
    prezzo REAL,
    UNIQUE(cod, id_cat) ON CONFLICT REPLACE
  )
''',
  };

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    for (var createQuery in tables.values) {
      await db.execute(createQuery);
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      switch (version) {
        case 3:
          // Check if column exists before adding
          if (!await _columnExists(db, tavoloTable, 'is_locked')) {
            await db.execute(
                'ALTER TABLE tavolo ADD COLUMN is_locked INTEGER DEFAULT 0');
          }
          break;
        case 4:
          // Check if column exists before adding
          if (!await _columnExists(db, tavoloTable, 'is_occupied')) {
            await db.execute(
                'ALTER TABLE tavolo ADD COLUMN is_occupied INTEGER DEFAULT 0');
          }
          break;
        case 8:
          await db.execute(tables['gruppi']!);
          break;
        case 9:
          await db.execute(tables['articoli']!);
          break;
        case 11:
          await db.execute(tables['varianti']!);
          break;
        case 14:
          // Check if column exists before adding
          if (!await _columnExists(db, 'varianti', 'prezzo')) {
            await db.execute('ALTER TABLE varianti ADD COLUMN prezzo REAL');
          }
          break;
      }
    }
  }

  // Check if column exists in the table
  Future<bool> _columnExists(
      Database db, String tableName, String columnName) async {
    final List<Map<String, dynamic>> columns =
        await db.rawQuery('PRAGMA table_info($tableName)');
    return columns.any((column) => column['name'] == columnName);
  }

  // Save filtered tavolos for a specific sala
  Future<void> saveAllTavolos(
      int salaId, List<Map<String, dynamic>> tavolos) async {
    await clearTavolosForSala(salaId);
    final batch = (await database).batch();
    for (var tavolo in tavolos) {
      batch.insert(
        tavoloTable,
        tavolo,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Clear tavolos for a specific sala
  Future<int> clearTavolosForSala(int salaId) async {
    Database db = await instance.database;
    return await db.delete(
      tavoloTable,
      where: '$tavoloIdSala = ?',
      whereArgs: [salaId],
    );
  }

  // Query all tavolos for a specific sala
  Future<List<Map<String, dynamic>>> queryTavolosBySala(int salaId) async {
    Database db = await instance.database;
    return await db.query(
      tavoloTable,
      where: '$tavoloIdSala = ?',
      whereArgs: [salaId],
    );
  }

  Future<List<Map<String, dynamic>>> queryAllSalas() async {
    Database db = await instance.database;
    return await db.query(salaTable);
  }

  Future<int> clearSalas() async {
    Database db = await instance.database;
    return await db.delete(salaTable);
  }

  // Save filtered tavolos (used in DataRepository)
  Future<List<Map<String, dynamic>>> queryBancoTavolosBySala(int salaId) async {
    Database db = await instance.database;
    return await db.query(
      tavoloTable,
      where: '$tavoloIdSala = ? AND $tavoloModBanco = ?',
      whereArgs: [salaId, 1],
    );
  }

  Future<int> clearTavolos() async {
    Database db = await instance.database;
    return await db.delete(tavoloTable);
  }

  Future<void> saveAllSalas(List<Map<String, dynamic>> salas) async {
    await clearSalas();
    final batch = (await database).batch();
    for (var sala in salas) {
      batch.insert(salaTable, sala);
    }
    await batch.commit(noResult: true);
  }

  Future<int> insertOrder(Map<String, dynamic> order) async {
    final db = await database;
    return await db.insert('orders', order);
  }

  Future<int> updateOrder(Map<String, dynamic> order) async {
    final db = await database;
    return await db.update(
      'orders',
      order,
      where: 'id = ?',
      whereArgs: [order['id']],
    );
  }

  Future<List<Map<String, dynamic>>> getOrdersForTable(int tavoloId) async {
    final db = await database;
    return await db.query(
      'orders',
      where: 'tavolo = ?',
      whereArgs: [tavoloId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> emptyOrdersForTable(int tavoloId) async {
    final db = await database;
    await db.delete(
      'orders',
      where: 'tavolo = ?',
      whereArgs: [tavoloId],
    );
    print('cleaned');
  }

  Future<void> updateTablePendingStatus(int tableId, int isPending) async {
    final db = await instance.database;
    await db.update(
      'tavolo',
      {
        'is_pending': isPending,
      },
      where: 'id = ?',
      whereArgs: [tableId],
    );
  }

  Future<void> saveAllOrdersForTable(
    int tavoloId,
    List<Map<String, dynamic>> orders,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('orders', where: 'tavolo = ?', whereArgs: [tavoloId]);
      for (var order in orders) {
        await txn.insert('orders', order);
      }
    });
  }

  Future<bool> orderExists(int orderId) async {
    final db = await database;
    final result = await db.query(
      'orders',
      where: 'id = ?',
      whereArgs: [orderId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> upsertOrder(Map<String, dynamic> order) async {
    final exists = await orderExists(order['id']);
    if (exists) {
      // Check if order needs update
      final existing = (await getOrdersForTable(
        order['tavolo'],
      ))
          .firstWhere((o) => o['id'] == order['id']);

      if (_ordersDiffer(existing, order)) {
        await updateOrder(order);
      }
    } else {
      await insertOrder(order);
    }
  }

  bool _ordersDiffer(
    Map<String, dynamic> existing,
    Map<String, dynamic> newOrder,
  ) {
    return existing['mov_prz'] != newOrder['mov_prz'] ||
        existing['mov_qta'] != newOrder['mov_qta'] ||
        existing['mov_aliiva'] != newOrder['mov_aliiva'] ||
        existing['is_coperto'] != newOrder['is_coperto'];
  }

  Future<void> upsertAllOrdersForTable(
    int tavoloId,
    List<Map<String, dynamic>> orders,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      // Get existing orders for this table
      final existingOrders = await txn.query(
        'orders',
        where: 'tavolo = ?',
        whereArgs: [tavoloId],
      );

      // Create a map of existing orders by ID for quick lookup
      final existingMap = {for (var o in existingOrders) o['id'] as int: o};

      for (var order in orders) {
        final orderId = order['id'] as int;
        if (existingMap.containsKey(orderId)) {
          // Update only if different
          if (_ordersDiffer(existingMap[orderId]!, order)) {
            await txn.update(
              'orders',
              order,
              where: 'id = ?',
              whereArgs: [orderId],
            );
          }
        } else {
          // Insert new order
          await txn.insert('orders', order);
        }
      }

      // Delete orders that are no longer present
      final newOrderIds = orders.map((o) => o['id'] as int).toSet();
      final ordersToDelete = existingOrders
          .where((o) => !newOrderIds.contains(o['id'] as int))
          .map((o) => o['id'] as int)
          .toList();

      if (ordersToDelete.isNotEmpty) {
        await txn.delete(
          'orders',
          where: 'id IN (${List.filled(ordersToDelete.length, '?').join(',')})',
          whereArgs: ordersToDelete,
        );
      }
    });
  }

  //categorie handling
  Future<void> saveAllGruppi(List<Map<String, dynamic>> gruppi) async {
    final db = await instance.database;
    final batch = db.batch();

    for (var gruppo in gruppi) {
      batch.insert(
          'gruppi',
          {
            'id': gruppo['id'],
            'des': gruppo['des'],
            'menu_pranzo': gruppo['menu_pranzo'],
            'menu_cena': gruppo['menu_cena'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> queryAllGruppi() async {
    final db = await instance.database;
    return await db.query('gruppi');
  }

  //articols handling
Future<void> saveAllArticoli(List<Map<String, dynamic>> articoli) async {
  final db = await instance.database;

  try {
    await db.transaction((txn) async {
      for (var articolo in articoli) {
        try {
          final validatedCat = _validateCategory(articolo['id_cat']);
          
          await txn.insert(
            'articoli',
            {
              'id': articolo['id'],
              'cod': articolo['cod']?.toString() ?? '',
              'des': articolo['des']?.toString() ?? '',
              'qta': int.tryParse(articolo['qta'].toString()) ?? 0,
              'prezzo': double.tryParse(articolo['prezzo'].toString()) ?? 0.0,
              'id_cat': validatedCat,
              'cat_des': articolo['cat_des']?.toString() ?? '',
              'id_ag': int.tryParse(articolo['id_ag'].toString()) ?? 0,
              'svincolo_sequenza': int.tryParse(articolo['svincolo_sequenza'].toString()) ?? 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (e) {
          print('❌ Error inserting article ${articolo['id']}: $e');
          print('Problematic data: ${articolo.toString()}');
        }
      }
    });
    
    // Verify insertion
    final counts = await db.rawQuery(
      'SELECT id_cat, COUNT(*) as count FROM articoli GROUP BY id_cat'
    );
    print('Post-insertion category distribution: $counts');
  } catch (e) {
    print('💥 Transaction failed: $e');
    rethrow;
  }
}

int _validateCategory(dynamic idCat) {
  if (idCat == null) {
    print('⚠️ Null category ID found');
    return -1; // Or your default category
  }
  return int.tryParse(idCat.toString()) ?? -1;
}



  // Query articoli by category ID
 Future<List<Map<String, dynamic>>> queryArticoliByCategory(int idCat) async {
  final db = await instance.database;
  
  // First verify the category exists
  final categoryCheck = await db.query(
    'articoli',
    distinct: true,
    columns: ['id_cat'],
    where: 'id_cat = ?',
    whereArgs: [idCat],
    limit: 1
  );

  if (categoryCheck.isEmpty) {
  
  
    return [];
  }

  return await db.query(
    'articoli',
    where: 'id_cat = ?',
    whereArgs: [idCat],
  );
}

  //varianti
 Future<void> saveAllvarianti(List<Map<String, dynamic>> varianti) async {
  final db = await instance.database;
  await db.transaction((txn) async {
    for (var varian in varianti) {
      await txn.insert(
        'varianti',
        {
          'cod': varian['cod'],
          'des': varian['des'],
          'id_cat': varian['id_cat'],
          'prezzo': varian['prezzo'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}

  //get variante by cat
  Future<List<Map<String, dynamic>>> queryvariantByCategory(int idCat) async {
    final db = await instance.database;
    return await db.query('varianti', where: 'id_cat = ?', whereArgs: [idCat]);
  }

  Future<void> saveImpostazioniPalm(List<Map<String, dynamic>> data) async {
    final db = await instance.database;

    for (var item in data) {
      // Check if a record with the same `pv` exists
      final existing = await db.query(
        'impostazioni_palm',
        where: 'pv = ?',
        whereArgs: [item['pv']],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        // Update the existing record
        await db.update(
          'impostazioni_palm',
          {
            'wsport': item['wsport'],
            'chiusura_palmare': item['chiusura_palmare'],
            'avanzamento_sequenza': item['avanzamento_sequenza'],
            'avanzamento_palmare': item['avanzamento_palmare'],
            'abilita_satispay': item['abilita_satispay'],
            'listino_palmari': item['listino_palmari'],
            'licenze_palmari': item['licenze_palmari'],
            'ristocomande_ver': item['ristocomande_ver'],
            'copertoPalm': item['copertoPalm'],
          },
          where: 'pv = ?',
          whereArgs: [item['pv']],
        );
      } else {
        // Insert new record
        await db.insert(
          'impostazioni_palm',
          {
            'wsport': item['wsport'],
            'chiusura_palmare': item['chiusura_palmare'],
            'avanzamento_sequenza': item['avanzamento_sequenza'],
            'avanzamento_palmare': item['avanzamento_palmare'],
            'pv': item['pv'],
            'abilita_satispay': item['abilita_satispay'],
            'listino_palmari': item['listino_palmari'],
            'licenze_palmari': item['licenze_palmari'],
            'ristocomande_ver': item['ristocomande_ver'],
            'copertoPalm': item['copertoPalm'],
          },
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> queryImpostazioniPalm() async {
    final db = await instance.database;
    return await db.query('impostazioni_palm');
  }

//operatore
  Future<void> saveOperatore(List<Map<String, dynamic>> data) async {
    final db = await instance.database;

    for (var item in data) {
      final List<Map<String, dynamic>> existing = await db.query(
        'operatore',
        where: 'id = ?',
        whereArgs: [item['id']],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        // Update existing record
        await db.update(
          'operatore',
          {
            'nome': item['nome'],
            'cognome': item['cognome'],
            'username': item['username'],
            'password': item['password'],
            'vis_lis': item['vis_lis'],
            'vis_cosu': item['vis_cosu'],
            'tipo_permesso': item['tipo_permesso'],
            'usa_terminale': item['usa_terminale'],
            'remember_token': item['remember_token'],
            'chiedere_password': item['chiedere_password'],
          },
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      } else {
        // Insert new record
        await db.insert(
          'operatore',
          {
            'id': item['id'],
            'nome': item['nome'],
            'cognome': item['cognome'],
            'username': item['username'],
            'password': item['password'],
            'vis_lis': item['vis_lis'],
            'vis_cosu': item['vis_cosu'],
            'tipo_permesso': item['tipo_permesso'],
            'usa_terminale': item['usa_terminale'],
            'remember_token': item['remember_token'],
            'chiedere_password': item['chiedere_password'],
          },
        );
      }
    }
  }

// Add this method to your DatabaseHelper class
Future<void> clearAllTables() async {
  final db = await database;
  await db.transaction((txn) async {

    for (var table in tables.keys) {
      try {
        await txn.delete(table);
      } catch (e) {
        print('Error clearing table $table: $e');
      }
    }
    
    await txn.delete('orders');
    await txn.delete('tavolo');
    await txn.delete('sala');
    await txn.delete('articoli');
    await txn.delete('gruppi');
    await txn.delete('varianti');
    await txn.delete('impostazioni_palm');
    await txn.delete('operatore');
  });
}

  Future<List<Map<String, dynamic>>> queryOperatore() async {
    final db = await instance.database;
    return await db.query('operatore');
  }
}
