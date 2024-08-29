import React, { useState } from 'react';
import './styles.css';

const modelName = process.env.REACT_APP_MODEL_NAME;

function App() {
  const [prompt, setPrompt] = useState('');
  const [response, setResponse] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setResponse('');  // Clear previous response

    try {
      const responseStream = await fetch('http://ecs-load-balancer.elb.localhost.localstack.cloud:4566/api/generate/', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          model: modelName,
          prompt: prompt,
          stream: true
        })
      });

      const reader = responseStream.body.getReader();
      const decoder = new TextDecoder();
      let done = false;

      while (!done) {
        const { value, done: readerDone } = await reader.read();
        if (readerDone) break;

        const chunk = decoder.decode(value, { stream: true });

        // Handle multiple JSON objects in a single chunk
        const lines = chunk.split('\n').filter(line => line.trim() !== '');

        for (let line of lines) {
          try {
            const json = JSON.parse(line);
            setResponse((prev) => prev + json.response);
            if (json.done) {
              done = true;
            }
          } catch (err) {
            console.error('Error parsing JSON:', err);
          }
        }
      }
    } catch (error) {
      console.error('Error:', error);
      setResponse('An error occurred.');
    } finally {
      setLoading(false);
    }
  };

  return (
      <div className="container">
        <div className="chatbot">
          <h1> 🦙 Chatbot</h1>
          <div className="content">
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
        </div>
      </div>
  );
}

export default App;
