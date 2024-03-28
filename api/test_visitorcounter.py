# test_visitorcounter.py inside the api/tests directory
import sys
sys.path.append('<absolute_path_to_your_project>/api/.python_packages/lib/site-packages')
import unittest
from unittest.mock import Mock, patch
import azure.functions as func
from function_app import app  # This imports the app

class TestVisitorCounterFunction(unittest.TestCase):

    @patch('function_app.os.getenv')
    @patch('function_app.TableServiceClient')
    def test_visitor_counter_function(self, mock_table_service_client, mock_getenv):
        # Mocking os.getenv to return a fake connection string
        mock_getenv.return_value = 'FakeConnectionString'

        # Setup mock TableServiceClient methods
        mock_client = mock_table_service_client.return_value
        mock_table_client = Mock()
        mock_client.get_table_client.return_value = mock_table_client

        # Mock entity retrieval and update
        mock_entity = {'Count': 5}
        mock_table_client.get_entity.return_value = mock_entity
        mock_table_client.update_entity = Mock()

        # Create a fake HttpRequest
        req = func.HttpRequest(
            method='GET',
            url='/api/visitorcounter',
            body=None,
            headers={'Content-Type': 'application/json'},
        )

        # Call the Azure Function
        response = app._func.visitorcounter(req)

        # Assertions to ensure the function behaved as expected
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_body().decode(), '6')
        mock_table_client.update_entity.assert_called_with({'PartitionKey': 'VisitorCounter', 'RowKey': 'Counter', 'Count': 6})

        # You should also add assertions to check that proper logging has happened, 
        # and that the TableServiceClient was initialized correctly.

if __name__ == '__main__':
    unittest.main()