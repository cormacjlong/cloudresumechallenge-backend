import unittest
from unittest.mock import patch, MagicMock
import azure.functions as func

from function_app import visitorcounter

class TestFunction(unittest.TestCase):

    @patch('os.getenv')
    @patch('azure.data.tables.TableServiceClient')
    def test_function_app(self, mock_table_service_client, mock_getenv):
        # Setup the fake connection string
        mock_getenv.return_value = 'DefaultEndpointsProtocol=https;AccountName=FakeAccountName;AccountKey=FakeAccountKey;EndpointSuffix=core.windows.net'
        
        # Setup the TableServiceClient and its return values
        mock_client = mock_table_service_client.return_value
        mock_table_client = MagicMock()

        # Mocking the entity to be returned by get_entity
        mock_entity = {'Count': 42}
        mock_table_client.get_entity.return_value = mock_entity
        mock_client.get_table_client.return_value = mock_table_client

        # Construct a mock HTTP request
        req = func.HttpRequest(method='GET', body=None, url='/api/visitorcounter', params={})
        
        # Call the function
        func_call = visitorcounter.build().get_user_function()
        resp = func_call(req)
        #resp = visitorcounter(req)

        # Assert the expected outcome
        self.assertEqual(resp.status_code, 200)
