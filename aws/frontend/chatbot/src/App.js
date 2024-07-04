import React, {useState} from 'react';
import axios from 'axios';
import './styles.css';

const modelName = process.env.REACT_APP_MODEL_NAME;
const lbDnsName = process.env.REACT_APP_LB_NAME

function App() {
    const [prompt, setPrompt] = useState('');
    const [response, setResponse] = useState('');
    const [loading, setLoading] = useState(false);

    const handleSubmit = async (e) => {
        e.preventDefault();
        setLoading(true);
        try {
            const result = await axios.post('http://' + lbDnsName + '/api/generate', {
                model: modelName,
                prompt: prompt,
                stream: false
            }, {
                headers: {
                    'Content-Type': 'application/json'
                }
            });
            setResponse(result.data.response);
        } catch (error) {
            console.error('Error:', error);
            setResponse('An error occurred.');
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="container">
            <h1>Chatbot</h1>
            <form onSubmit={handleSubmit}>
                <div>
                    <label htmlFor="prompt">Prompt:</label>
                    <input
                        type="text"
                        id="prompt"
                        value={prompt}
                        onChange={(e) => setPrompt(e.target.value)}
                    />
                </div>
                <button type="submit">Send</button>
            </form>
            {loading && <div className="loading">Thinking of the answer...</div>}
            {response && (
                <div className="response">
                    <h2>Response:</h2>
                    <p>{response}</p>
                </div>
            )}
        </div>
    );
}

export default App;
