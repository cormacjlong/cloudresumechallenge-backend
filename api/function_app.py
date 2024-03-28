import logging
import os
import azure.functions as func
from azure.data.tables import TableServiceClient
from azure.identity import DefaultAzureCredential

# Configure logging to output to the standard output stream
logging.basicConfig(level=logging.INFO)

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

@app.route(route="visitorcounter")
def visitorcounter(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request to increment the visitor count.')
    return func.HttpResponse("Temporary response", status_code=200)

    # Ensure the cosmos_endpoint environment variable is read correctly
    cosmos_connection_string = os.getenv("CUSTOMCONNSTR_Default")
    if not cosmos_connection_string:
        logging.error('COSMOS_ENDPOINT environment variable is not set.')
        return func.HttpResponse(
            "COSMOS_ENDPOINT environment variable is not set.",
            status_code=500
        )

    try:
        # Initialize DefaultAzureCredential which will use the managed identity
        credential = DefaultAzureCredential()

        # Initialize TableServiceClient using the managed identity credential
        table_service_client = TableServiceClient.from_connection_string(conn_str=cosmos_connection_string)
        logging.info('TableServiceClient initialized.')

        # Reference to the table
        table_client = table_service_client.get_table_client(table_name="VisitorCountTable")
        logging.info('Reference to the table obtained.')

        try:
            # Attempt to fetch the existing count
            entity = table_client.get_entity(partition_key="VisitorCounter", row_key="Counter")
            count = entity['Count']
            logging.info(f'Current count fetched: {count}')
        except Exception as e:
            # If not found, initialize the count
            logging.info('Entity not found. Initializing the visitor count.')
            count = 0
            entity = {
                'PartitionKey': 'VisitorCounter',
                'RowKey': 'Counter',
                'Count': count
            }
            table_client.create_entity(entity=entity)
            logging.info('Visitor count initialized.')

        # Increment the count
        count += 1
        entity['Count'] = count
        logging.info(f'Incremented count: {count}')

        # Update the entity in the table
        table_client.update_entity(entity)
        logging.info('Entity updated in the table.')

    except Exception as e:
        logging.error(f'An error occurred: {str(e)}')
        return func.HttpResponse(
            f"An error occurred: {str(e)}",
            status_code=500
        )

    # Return the new count as a response
    logging.info(f'Returning the new visitor count: {count}')
    return func.HttpResponse(f"{count}", status_code=200)
