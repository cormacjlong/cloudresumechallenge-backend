import unittest
from unittest.mock import patch, MagicMock
import azure.functions as func

from function_app import visitorcounter

class TestFunction(unittest.TestCase):

    @patch('os.getenv')
    @patch('azure.data.tables.TableServiceClient.from_connection_string')
    def test_function_app_withentity(self, mock_from_conn_str, mock_getenv):
        # Setup the mock connection string
        mock_getenv.return_value = 'NotAnActualSecret;'
        
        # Setup the TableServiceClient mock
        existing_count = 42
        mock_table_client = MagicMock()
        mock_from_conn_str.return_value.get_table_client.return_value = mock_table_client

        # Setup mock behaviors for the table client
        mock_entity = {'PartitionKey': 'VisitorCounter', 'RowKey': 'Counter', 'Count': existing_count}
        mock_table_client.get_entity.return_value = mock_entity
        mock_table_client.create_entity.return_value = None
        mock_table_client.update_entity.return_value = None

        # Construct a mock HTTP request
        req = func.HttpRequest(method='GET', body=None, url='/api/visitorcounter', params={})
        
        # Call the function
        func_call = visitorcounter.build().get_user_function()
        resp = func_call(req)

        # Assert the expected outcome
        self.assertIsNotNone(resp, "Function returned None instead of a response object")
        expected_count = existing_count + 1  # Expecting the count to increment
        self.assertEqual(resp.status_code, 200, "Function returned a HTTP status code other than 200")
        self.assertIn(str(expected_count), resp.get_body().decode("utf-8"), "The visitor count should be incremented.")
