import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:graphql/client.dart';
import 'package:http/io_client.dart';
import 'dart:io';

void main() {
  HttpOverrides.global =
      MyHttpOverrides(); // so Image.network works with self-signed certs in emulator
  runApp(const MyApp());
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ioc = HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    final httpClient = IOClient(ioc);

    final httpLink = HttpLink(
      'https://rickandmortyapi.com/graphql',
      httpClient: httpClient,
    );

    final client = GraphQLClient(
      cache: GraphQLCache(),
      link: httpLink,
    );

    return MaterialApp(
      title: 'Paginated GraphQL List',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: ItemListScreen(client: client),
    );
  }
}

class ItemListScreen extends StatefulWidget {
  final GraphQLClient client;

  const ItemListScreen({super.key, required this.client});

  @override
  State<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends State<ItemListScreen> {
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> items = [];
  bool isLoading = false;
  bool hasMore = true;

  int currentPage = 1; // <-- page-based pagination
  final int pageSize = 20;

  @override
  void initState() {
    super.initState();
    _fetchItems();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !isLoading &&
          hasMore) {
        _fetchItems();
      }
    });
  }

  Future<void> _fetchItems() async {
    setState(() => isLoading = true);

    final query = gql("""query {
        characters(page: $currentPage, filter: { name: "rick" }) {
      info {
        count
      }
      results {
        name
        image
        species
        origin {
          name
        }
      }
    }
  }
  """);

    final result = await widget.client.query(
      QueryOptions(document: query),
    );

    if (result.hasException) {
      debugPrint(result.exception.toString());
      setState(() => isLoading = false);
      return;
    }

    final fetched = List<Map<String, dynamic>>.from(
      result.data?['characters']['results'] ?? [],
    );

    setState(() {
      currentPage++; // move to next page
      items.addAll(fetched);
      isLoading = false;
      if (fetched.length < pageSize) {
        hasMore = false; // no more data
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Graphql Example", style: TextStyle(color: Colors.white),), backgroundColor: Theme.of(context).primaryColor),
      body: ListView.builder(
        controller: _scrollController,
        itemCount: items.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final item = items[index];
          return ItemTile(item: item);
        },
      ),
    );
  }
}

class ItemTile extends StatelessWidget {
  final Map<String, dynamic> item;

  const ItemTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(36), // rounded corners
          child: CachedNetworkImage(
            imageUrl: item['image'],
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            placeholder: (context, url) => const SizedBox(
              width: 60,
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          ),
        ),
        title: Text(
          item['name'] ?? '',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          item['origin']['name'] ?? '',
          style: Theme.of(context).textTheme.bodyMedium, // subtitle style
        ),
        trailing: Badge(
          label: Text(item['species'] ?? ''),
          backgroundColor:
              (item['species'] == 'Human' ? Colors.blue : Colors.red.shade800),
        ));
  }
}
