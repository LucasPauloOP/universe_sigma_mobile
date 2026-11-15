import 'fake_server.dart';

const testUser = {'id': 'u', 'email': 'a@b.com', 'name': 'A', 'createdAt': '2026-01-01T00:00:00.000Z'};

FakeServer commonServer({bool loggedIn = true}) => FakeServer({
      'POST /auth/login': (o) => (200, {'token': 'tk', 'refreshToken': 'rt', 'user': testUser}),
      'GET /auth/me': (o) => loggedIn ? (200, testUser) : (401, {'success': false, 'message': 'Token inválido'}),
      'GET /universes': (o) => (200, [
            {'id': 'u1', 'name': 'Meu Universe', 'description': 'Save principal', 'createdAt': '2026-01-01T00:00:00.000Z'}
          ]),
      'GET /universes/u1/wrestlers': (o) => (200, page([{'id': 'w1', 'name': 'John Cena', 'gender': 'M'}])),
      'GET /universes/u1/teams': (o) => (200, page([])),
      'GET /universes/u1/titles': (o) => (200, page([])),
      'GET /universes/u1/shows': (o) => (200, page([])),
      'GET /universes/u1/episodes': (o) => (200, page([])),
      'GET /universes/u1/tournaments': (o) => (200, page([])),
      'GET /universes/u1/rivalries': (o) => (200, page([])),
      'GET /universes/u1/title-reigns': (o) => (200, page([
            {
              'id': 'r1', 'endDate': null, 'startDate': '2026-03-29T00:00:00.000Z',
              'title': {'name': 'World Heavyweight'},
              'holders': [{'wrestler': {'name': 'John Cena'}}],
            }
          ])),
      'GET /universes/u1/seasons': (o) => (200, page([])),
    });

