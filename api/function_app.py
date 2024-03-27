import logging
import azure.functions as func
from azure.data.tables import TableServiceClient
from azure.identity import DefaultAzureCredential

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request to increment the visitor count.')

    # Initialize DefaultAzureCredential which will use the managed identity
    credential = DefaultAzureCredential()

    # Initialize TableServiceClient using the managed identity credential
    table_service_client = TableServiceClient(
        account_url="https://cosmos-dev-crcbackend-b7a8.table.cosmos.azure.com:443/",
        credential=credential
    )

    # Reference to the table
    table_client = table_service_client.get_table_client(table_name="VisitorCountTable")

    try:
        # Attempt to fetch the existing count
        entity = table_client.get_entity(partition_key="VisitorCounter", row_key="Counter")
        count = entity['Count']
    except Exception as e:
        # If not found, initialize the count
        logging.info('Initializing the visitor count.')
        count = 0
        entity = {
            'PartitionKey': 'VisitorCounter',
            'RowKey': 'Counter',
            'Count': count
        }
        table_client.create_entity(entity=entity)

    # Increment the count
    count += 1
    entity['Count'] = count

    # Update the entity in the table
    table_client.update_entity(entity)

    # Return the new count as a response
    return func.HttpResponse(f"Visitor count: {count}", status_code=200)
