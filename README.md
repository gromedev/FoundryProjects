# Complete Guide: Train Models for Foundry Local on Mac M2 Pro

## For Someone Who Knows Nothing About LLMs

**Your Machine:** MacBook Pro M2 Pro (Mac14,9) with 32GB RAM  
**Time Required:** 3-4 hours for complete setup  
**Difficulty:** Follow the commands exactly. Copy and paste. Don't improvise.

---

## Table of Contents

1. [What You're Going to Build](#part-1-what-youre-going-to-build)
2. [Prerequisites - Install Everything](#part-2-prerequisites)
3. [RAG Setup - Document Q&A System](#part-3-rag-setup)
4. [Fine-Tuning with PyTorch](#part-4-fine-tuning-with-pytorch)
5. [Convert to ONNX with Olive](#part-5-convert-to-onnx-with-olive)
6. [Import to Foundry Local](#part-6-import-to-foundry-local)
7. [Troubleshooting](#part-7-troubleshooting)
8. [Quick Reference](#part-8-quick-reference)

---

## Part 1: What You're Going to Build

### The Big Picture

You want an AI that:
1. **Knows your textbooks** - Can answer questions about your specific documents
2. **Talks like an expert** - Responds in the style/terminology you train it with
3. **Runs on your Mac** - Everything local, private, no cloud needed
4. **Uses Foundry Local** - Microsoft's on-device AI platform

### The Two Systems You'll Build

**System 1: RAG (Document Retrieval)**
- What it does: Searches your documents and feeds relevant info to the AI
- Why you need it: So the AI can accurately cite YOUR textbooks
- Example: "What does page 47 say about Azure firewalls?"

**System 2: Fine-Tuned Model**
- What it does: Teaches the AI to respond in a specific style/tone
- Why you need it: So the AI talks like a Microsoft security expert
- Example: The AI uses proper technical terminology and structured responses

### The Complete Pipeline

```
YOUR DOCUMENTS (PDFs, textbooks)
        |
        v
+------------------+     +-------------------+
| RAG System       |     | Fine-Tuning       |
| (LlamaIndex)     |     | (PyTorch)         |
| Retrieves WHAT   |     | Changes HOW the   |
| to answer with   |     | model responds    |
+------------------+     +-------------------+
        |                         |
        |                         v
        |               +-------------------+
        |               | Convert to ONNX   |
        |               | (Microsoft Olive) |
        |               +-------------------+
        |                         |
        v                         v
+------------------------------------------+
|          Foundry Local                   |
|    (Runs the model on your Mac)         |
+------------------------------------------+
        |
        v
    YOUR ANSWER
```

### Why Not Just Fine-Tune?

**Critical Understanding:**
- Fine-tuning does NOT make the AI "memorize" your textbooks
- Fine-tuning only changes HOW the AI responds (style, tone, format)
- For factual recall from documents, you MUST use RAG

**Best approach:** Use BOTH systems together.

---

## Part 2: Prerequisites

### 2.1 Install Homebrew

Open Terminal (Command + Space, type "Terminal", press Enter).

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Wait for it to finish.** It will show commands to add Homebrew to your PATH. Run those commands (they look like this):

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Verify:

```bash
brew --version
```

You should see a version number like "Homebrew 4.x.x"

### 2.2 Install Python 3.11

```bash
brew install python@3.11
```

Verify:

```bash
python3.11 --version
```

Should show `Python 3.11.x`

### 2.3 Install Git

```bash
brew install git
```

### 2.4 Install Foundry Local

```bash
brew tap microsoft/foundrylocal
brew install foundrylocal
```

Verify:

```bash
foundry --version
```

You should see version information for Foundry Local.

### 2.5 Create Project Directory

```bash
mkdir -p ~/foundry-training
cd ~/foundry-training
```

From now on, this is your working directory. All files will go here.

### 2.6 Create Python Virtual Environment

```bash
python3.11 -m venv venv
source venv/bin/activate
```

Your terminal prompt should now show `(venv)` at the beginning.

**CRITICAL:** Every time you open a new terminal to work on this project, run:

```bash
cd ~/foundry-training
source venv/bin/activate
```

### 2.7 Upgrade pip

```bash
pip install --upgrade pip
```

### 2.8 Install Python Packages for RAG

```bash
pip install llama-index llama-index-llms-openai llama-index-embeddings-huggingface chromadb pypdf
```

This takes 5-10 minutes. Ignore warnings about pip versions.

### 2.9 Install PyTorch for Mac

```bash
pip install torch torchvision torchaudio
```

This is a large download (2-3 GB). Be patient.

### 2.10 Install Training Libraries

```bash
pip install transformers peft accelerate datasets bitsandbytes sentencepiece protobuf
```

### 2.11 Install Microsoft Olive

```bash
pip install olive-ai onnxruntime onnxruntime-genai huggingface_hub
```

### 2.12 Login to Hugging Face

You need a free Hugging Face account to download models.

1. Go to https://huggingface.co/settings/tokens
2. Create a token with "Read" permissions
3. Copy the token

Now in Terminal:

```bash
huggingface-cli login
```

Paste your token when prompted. Press Enter.

### 2.13 Download a Test Model

Let's verify Foundry Local works:

```bash
foundry model list
```

This shows available models. Pick a small one to test:

```bash
foundry model run phi-3.5-mini
```

Type a question like "What is the capital of France?" and press Enter.

Press Ctrl+C to exit when done.

**If this worked, you're ready to proceed.**

---

## Part 3: RAG Setup

This section builds the document Q&A system.

### 3.1 Create Directories

```bash
cd ~/foundry-training
mkdir -p documents
mkdir -p index_storage
```

### 3.2 Add Your Documents

Copy your PDFs and textbooks into `~/foundry-training/documents/`

**Supported formats:**
- PDF (.pdf)
- Word (.docx)
- Text (.txt)
- Markdown (.md)
- Code files (.py, .ps1, etc.)

**Example commands:**

```bash
# Copy PDFs from Downloads
cp ~/Downloads/*.pdf ~/foundry-training/documents/

# Copy a folder of textbooks
cp -r ~/Books/Azure-Security/ ~/foundry-training/documents/

# Clone a GitHub repository
cd ~/foundry-training/documents
git clone https://github.com/MicrosoftDocs/azure-docs.git
cd ~/foundry-training
```

### 3.3 Create the RAG Script

```bash
cd ~/foundry-training
cat > rag_assistant.py << 'ENDOFSCRIPT'
#!/usr/bin/env python3
"""
RAG Assistant - Query your documents using Foundry Local
"""

import os
import sys
from pathlib import Path

from llama_index.core import (
    VectorStoreIndex,
    SimpleDirectoryReader,
    StorageContext,
    load_index_from_storage,
    Settings
)
from llama_index.llms.openai import OpenAI
from llama_index.embeddings.huggingface import HuggingFaceEmbedding

# === CONFIGURATION ===
DOCUMENTS_DIR = os.path.expanduser("~/foundry-training/documents")
INDEX_DIR = os.path.expanduser("~/foundry-training/index_storage")

# Foundry Local runs on localhost:5273 by default
FOUNDRY_LOCAL_URL = "http://localhost:5273/v1"
MODEL_NAME = "phi-3.5-mini"  # Change to your fine-tuned model name later

def setup_llm():
    """Configure Foundry Local as the LLM"""
    print("Setting up connection to Foundry Local...")
    
    # Configure LlamaIndex to use Foundry Local (OpenAI-compatible API)
    llm = OpenAI(
        api_base=FOUNDRY_LOCAL_URL,
        api_key="not-used",  # Foundry Local doesn't need API key
        model=MODEL_NAME
    )
    
    embed_model = HuggingFaceEmbedding(
        model_name="BAAI/bge-small-en-v1.5"
    )
    
    Settings.llm = llm
    Settings.embed_model = embed_model
    Settings.chunk_size = 1024
    Settings.chunk_overlap = 200
    
    print(f"Using model: {MODEL_NAME}")
    return llm, embed_model

def build_index():
    """Load documents and build the vector index"""
    print(f"\nLoading documents from: {DOCUMENTS_DIR}")
    
    if not os.path.exists(DOCUMENTS_DIR):
        print(f"ERROR: Documents directory not found: {DOCUMENTS_DIR}")
        print("Create it and add your documents first.")
        sys.exit(1)
    
    documents = SimpleDirectoryReader(
        input_dir=DOCUMENTS_DIR,
        recursive=True,
        required_exts=[".pdf", ".txt", ".md", ".docx", ".py", ".ps1", ".json"]
    ).load_data()
    
    if not documents:
        print("ERROR: No documents found!")
        print(f"Add PDF, text, or Word files to: {DOCUMENTS_DIR}")
        sys.exit(1)
    
    print(f"Loaded {len(documents)} document chunks")
    print("Building vector index... (this may take a while)")
    
    index = VectorStoreIndex.from_documents(documents, show_progress=True)
    
    # Save the index
    os.makedirs(INDEX_DIR, exist_ok=True)
    index.storage_context.persist(persist_dir=INDEX_DIR)
    
    print(f"Index saved to: {INDEX_DIR}")
    return index

def load_existing_index():
    """Load previously built index"""
    print(f"Loading existing index from: {INDEX_DIR}")
    storage_context = StorageContext.from_defaults(persist_dir=INDEX_DIR)
    index = load_index_from_storage(storage_context)
    print("Index loaded successfully")
    return index

def query_documents(index, query_text):
    """Query the index and return response"""
    query_engine = index.as_query_engine(
        similarity_top_k=5,
        response_mode="tree_summarize"
    )
    
    response = query_engine.query(query_text)
    return response

def interactive_mode(index):
    """Interactive Q&A session"""
    print("\n" + "="*70)
    print("RAG Assistant Ready!")
    print("Ask questions about your documents.")
    print("Type 'quit' or 'exit' to stop.")
    print("="*70 + "\n")
    
    while True:
        try:
            query = input("\n🤔 Your Question: ").strip()
            
            if query.lower() in ['quit', 'exit', 'q']:
                print("\nGoodbye!")
                break
            
            if not query:
                continue
            
            print("\n🔍 Searching documents...")
            response = query_documents(index, query)
            
            print("\n📝 Answer:")
            print("-" * 70)
            print(response)
            print("-" * 70)
            
            # Show sources
            if hasattr(response, 'source_nodes') and response.source_nodes:
                print("\n📚 Sources:")
                for i, node in enumerate(response.source_nodes, 1):
                    metadata = node.node.metadata
                    file_name = metadata.get('file_name', 'Unknown')
                    print(f"  {i}. {file_name}")
        
        except KeyboardInterrupt:
            print("\n\nGoodbye!")
            break
        except Exception as e:
            print(f"\n❌ Error: {e}")
            print("Try rephrasing your question.")

def main():
    """Main function"""
    import argparse
    
    parser = argparse.ArgumentParser(description="RAG Assistant for Foundry Local")
    parser.add_argument('--rebuild', action='store_true', 
                       help='Rebuild the index from documents')
    parser.add_argument('--query', type=str,
                       help='Single query mode (non-interactive)')
    
    args = parser.parse_args()
    
    # Setup LLM
    setup_llm()
    
    # Build or load index
    if args.rebuild or not os.path.exists(INDEX_DIR):
        index = build_index()
    else:
        index = load_existing_index()
    
    # Query mode
    if args.query:
        response = query_documents(index, args.query)
        print(response)
    else:
        interactive_mode(index)

if __name__ == "__main__":
    main()
ENDOFSCRIPT
```

Make it executable:

```bash
chmod +x rag_assistant.py
```

### 3.4 Test RAG System

First, make sure Foundry Local is running with a model:

**Open a NEW terminal window** (Command + T in Terminal). In this new window:

```bash
foundry service start
foundry model load phi-3.5-mini
```

Leave this terminal open and go back to your original terminal.

Now build the index:

```bash
cd ~/foundry-training
source venv/bin/activate  # If not already activated
python rag_assistant.py --rebuild
```

This will take 10-30 minutes depending on how many documents you have.

When done, test it:

```bash
python rag_assistant.py
```

Ask a question about your documents. The AI should answer using information from your files.

Type `quit` when done.

**If this works, your RAG system is ready!**

---

## Part 4: Fine-Tuning with PyTorch

This section teaches the model to respond in your desired style.

### 4.1 Create Training Data Directory

```bash
cd ~/foundry-training
mkdir -p training_data
```

### 4.2 Prepare Training Data

You need examples of how you want the model to respond. Format: JSONL (one JSON object per line)

Create the file:

```bash
cat > training_data/train.jsonl << 'EOF'
{"messages": [{"role": "user", "content": "What is Azure Active Directory?"}, {"role": "assistant", "content": "Azure Active Directory (Azure AD) is Microsoft's cloud-based identity and access management service. It provides: 1) Single sign-on (SSO) capabilities across cloud and on-premises applications, 2) Multi-factor authentication (MFA) for enhanced security, 3) Conditional access policies based on user risk and device state, 4) Identity protection using machine learning-based threat detection. Azure AD integrates with Microsoft 365, Azure services, and thousands of SaaS applications."}]}
{"messages": [{"role": "user", "content": "How do I secure Azure storage?"}, {"role": "assistant", "content": "Azure Storage security follows the defense-in-depth principle with multiple layers: 1) Encryption: Data is encrypted at rest using 256-bit AES encryption and in transit using TLS 1.2+, 2) Access Control: Use Azure RBAC to grant least-privilege access and implement storage account keys rotation, 3) Network Security: Enable firewall rules, virtual network service endpoints, and private endpoints, 4) Advanced Threat Protection: Enable Microsoft Defender for Storage to detect anomalies, 5) Audit Logging: Use Azure Monitor and Storage Analytics for compliance tracking."}]}
{"messages": [{"role": "user", "content": "What's a virtual network?"}, {"role": "assistant", "content": "An Azure Virtual Network (VNet) is a logically isolated network within the Azure cloud. Key characteristics: 1) IP Address Space: You define private IP address ranges (RFC 1918 compliant), 2) Subnets: Segment the VNet into multiple subnets for resource organization and security, 3) Network Security Groups (NSGs): Apply inbound/outbound traffic rules at subnet or NIC level, 4) Connectivity Options: VNet peering for VNet-to-VNet, VPN Gateway for site-to-site connections, ExpressRoute for dedicated private connections, 5) Service Endpoints: Secure direct connectivity to Azure PaaS services."}]}
EOF
```

**Add more examples!** The file above has only 3 examples. For good results, you need **50-100+ examples**.

Each example should show:
- A realistic question someone might ask
- The kind of answer you want the model to give (style, detail level, terminology)

Create validation data:

```bash
cat > training_data/valid.jsonl << 'EOF'
{"messages": [{"role": "user", "content": "What is Azure Firewall?"}, {"role": "assistant", "content": "Azure Firewall is a cloud-native, stateful firewall-as-a-service (FWaaS) providing: 1) Network-level protection with allow/deny rules for IP addresses and ports, 2) Application-level filtering using FQDNs and web categories, 3) Threat intelligence-based filtering to block traffic from/to known malicious IPs, 4) High availability with built-in redundancy across availability zones, 5) Integration with Azure Monitor for logging and analytics. It supports both traditional network security rules and modern application-aware policies."}]}
EOF
```

### 4.3 Create Fine-Tuning Script

```bash
cat > train_model.py << 'ENDOFSCRIPT'
#!/usr/bin/env python3
"""
Fine-tune a model using PyTorch and PEFT (LoRA)
Optimized for Mac M2 Pro
"""

import os
import json
import torch
from datasets import load_dataset
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    TrainingArguments,
    Trainer,
    DataCollatorForLanguageModeling,
    BitsAndBytesConfig
)
from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training

# === CONFIGURATION ===
BASE_MODEL = "mistralai/Mistral-7B-Instruct-v0.3"  # Good for 32GB RAM
OUTPUT_DIR = "./fine_tuned_model"
TRAINING_DATA = "./training_data"

def load_and_prepare_model():
    """Load base model with quantization for M2 Pro"""
    print(f"Loading base model: {BASE_MODEL}")
    
    # 4-bit quantization to fit in 32GB RAM
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_use_double_quant=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.float16
    )
    
    model = AutoModelForCausalLM.from_pretrained(
        BASE_MODEL,
        quantization_config=bnb_config,
        device_map="auto",
        trust_remote_code=True
    )
    
    tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL)
    tokenizer.pad_token = tokenizer.eos_token
    tokenizer.padding_side = "right"
    
    return model, tokenizer

def prepare_lora_model(model):
    """Add LoRA adapters for efficient fine-tuning"""
    print("Configuring LoRA...")
    
    model.gradient_checkpointing_enable()
    model = prepare_model_for_kbit_training(model)
    
    lora_config = LoraConfig(
        r=16,  # Rank
        lora_alpha=32,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
        lora_dropout=0.05,
        bias="none",
        task_type="CAUSAL_LM"
    )
    
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()
    
    return model

def load_training_data(tokenizer):
    """Load and tokenize training data"""
    print(f"Loading training data from: {TRAINING_DATA}")
    
    dataset = load_dataset('json', data_files={
        'train': f'{TRAINING_DATA}/train.jsonl',
        'validation': f'{TRAINING_DATA}/valid.jsonl'
    })
    
    def format_chat(examples):
        """Convert messages to chat format"""
        texts = []
        for messages in examples['messages']:
            # Format as instruction-response pairs
            text = ""
            for msg in messages:
                if msg['role'] == 'user':
                    text += f"<s>[INST] {msg['content']} [/INST] "
                elif msg['role'] == 'assistant':
                    text += f"{msg['content']}</s>"
            texts.append(text)
        return {'text': texts}
    
    dataset = dataset.map(format_chat, batched=True, remove_columns=['messages'])
    
    def tokenize(examples):
        """Tokenize the text"""
        return tokenizer(
            examples['text'],
            truncation=True,
            max_length=2048,
            padding="max_length"
        )
    
    tokenized_dataset = dataset.map(
        tokenize,
        batched=True,
        remove_columns=['text']
    )
    
    return tokenized_dataset

def train(model, tokenizer, dataset):
    """Train the model"""
    print("Starting training...")
    
    training_args = TrainingArguments(
        output_dir=OUTPUT_DIR,
        num_train_epochs=3,
        per_device_train_batch_size=1,
        gradient_accumulation_steps=4,
        learning_rate=2e-4,
        fp16=True,  # Use mixed precision for M2 Pro
        logging_steps=10,
        save_strategy="epoch",
        evaluation_strategy="epoch",
        warmup_steps=50,
        lr_scheduler_type="cosine",
        optim="adamw_torch",
        report_to="none"  # Disable wandb
    )
    
    data_collator = DataCollatorForLanguageModeling(
        tokenizer=tokenizer,
        mlm=False
    )
    
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=dataset['train'],
        eval_dataset=dataset['validation'],
        data_collator=data_collator
    )
    
    trainer.train()
    
    # Save the final model
    print(f"\nSaving model to: {OUTPUT_DIR}")
    trainer.save_model(OUTPUT_DIR)
    tokenizer.save_pretrained(OUTPUT_DIR)
    
    print("\n✅ Training complete!")
    return trainer

def main():
    """Main training pipeline"""
    print("="*70)
    print("Fine-Tuning Script for Foundry Local")
    print("="*70)
    
    # Load model
    model, tokenizer = load_and_prepare_model()
    
    # Add LoRA
    model = prepare_lora_model(model)
    
    # Load data
    dataset = load_training_data(tokenizer)
    
    print(f"\nTraining samples: {len(dataset['train'])}")
    print(f"Validation samples: {len(dataset['validation'])}")
    
    if len(dataset['train']) < 10:
        print("\n⚠️  WARNING: Very few training examples!")
        print("For best results, add 50-100+ examples to train.jsonl")
        response = input("Continue anyway? (yes/no): ")
        if response.lower() != 'yes':
            print("Exiting. Add more training data and try again.")
            return
    
    # Train
    trainer = train(model, tokenizer, dataset)
    
    print("\n" + "="*70)
    print("Next steps:")
    print("1. Test your model with: python test_model.py")
    print("2. Convert to ONNX with: python convert_to_onnx.py")
    print("="*70)

if __name__ == "__main__":
    main()
ENDOFSCRIPT
```

Make it executable:

```bash
chmod +x train_model.py
```

### 4.4 Create Test Script

```bash
cat > test_model.py << 'ENDOFSCRIPT'
#!/usr/bin/env python3
"""
Test the fine-tuned model before converting to ONNX
"""

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel

MODEL_PATH = "./fine_tuned_model"
BASE_MODEL = "mistralai/Mistral-7B-Instruct-v0.3"

def load_model():
    """Load the fine-tuned model"""
    print("Loading model...")
    
    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH)
    
    base_model = AutoModelForCausalLM.from_pretrained(
        BASE_MODEL,
        torch_dtype=torch.float16,
        device_map="auto"
    )
    
    model = PeftModel.from_pretrained(base_model, MODEL_PATH)
    model = model.merge_and_unload()  # Merge LoRA weights
    
    print("Model loaded!")
    return model, tokenizer

def generate_response(model, tokenizer, prompt):
    """Generate a response"""
    formatted_prompt = f"<s>[INST] {prompt} [/INST] "
    
    inputs = tokenizer(formatted_prompt, return_tensors="pt").to(model.device)
    
    outputs = model.generate(
        **inputs,
        max_new_tokens=500,
        temperature=0.7,
        top_p=0.9,
        do_sample=True
    )
    
    response = tokenizer.decode(outputs[0], skip_special_tokens=True)
    # Extract just the response part
    response = response.split("[/INST]")[-1].strip()
    
    return response

def main():
    """Interactive testing"""
    model, tokenizer = load_model()
    
    print("\n" + "="*70)
    print("Fine-Tuned Model Test")
    print("Type 'quit' to exit")
    print("="*70 + "\n")
    
    while True:
        prompt = input("\n🤔 Your Question: ").strip()
        
        if prompt.lower() in ['quit', 'exit', 'q']:
            break
        
        if not prompt:
            continue
        
        print("\n🤖 Generating response...")
        response = generate_response(model, tokenizer, prompt)
        
        print("\n📝 Response:")
        print("-" * 70)
        print(response)
        print("-" * 70)

if __name__ == "__main__":
    main()
ENDOFSCRIPT
```

Make it executable:

```bash
chmod +x test_model.py
```

### 4.5 Run Training

**IMPORTANT:** Training will take 2-4 hours on your M2 Pro.

```bash
cd ~/foundry-training
source venv/bin/activate
python train_model.py
```

You'll see progress updates every few steps. The loss should decrease over time.

When complete, test it:

```bash
python test_model.py
```

Try asking questions similar to your training data. The responses should match your desired style.

Press Ctrl+C to exit when done.

---

## Part 5: Convert to ONNX with Olive

Now convert your trained model to ONNX format for Foundry Local.

### 5.1 Merge LoRA Adapters First

```bash
cat > merge_model.py << 'ENDOFSCRIPT'
#!/usr/bin/env python3
"""
Merge LoRA adapters into base model for ONNX conversion
"""

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel

BASE_MODEL = "mistralai/Mistral-7B-Instruct-v0.3"
LORA_MODEL = "./fine_tuned_model"
OUTPUT_PATH = "./merged_model"

print("Loading base model...")
base_model = AutoModelForCausalLM.from_pretrained(
    BASE_MODEL,
    torch_dtype=torch.float16,
    device_map="auto"
)

print("Loading LoRA adapters...")
model = PeftModel.from_pretrained(base_model, LORA_MODEL)

print("Merging...")
merged_model = model.merge_and_unload()

print(f"Saving merged model to: {OUTPUT_PATH}")
merged_model.save_pretrained(OUTPUT_PATH)

tokenizer = AutoTokenizer.from_pretrained(LORA_MODEL)
tokenizer.save_pretrained(OUTPUT_PATH)

print("✅ Merge complete!")
print(f"Merged model saved to: {OUTPUT_PATH}")
ENDOFSCRIPT

chmod +x merge_model.py
python merge_model.py
```

This will take 5-10 minutes.

### 5.2 Create Olive Configuration

```bash
cat > olive_config.json << 'EOF'
{
  "input_model": {
    "type": "HfModel",
    "model_path": "./merged_model",
    "task": "text-generation"
  },
  "systems": {
    "local_system": {
      "type": "LocalSystem",
      "accelerators": [
        {
          "execution_providers": [
            "CPUExecutionProvider"
          ]
        }
      ]
    }
  },
  "passes": {
    "builder": {
      "type": "ModelBuilder",
      "config": {
        "precision": "int4"
      }
    }
  },
  "host": "local_system",
  "target": "local_system",
  "cache_dir": "cache",
  "output_dir": "onnx_model"
}
EOF
```

### 5.3 Convert to ONNX

**This is the most complex step and takes 30-60 minutes.**

```bash
olive auto-opt \
  --model_name_or_path ./merged_model \
  --trust_remote_code \
  --output_path ./onnx_model \
  --device cpu \
  --provider CPUExecutionProvider \
  --use_ort_genai \
  --precision int4 \
  --log_level 1
```

**What's happening:**
- Olive reads your PyTorch model
- Converts all operations to ONNX format
- Applies quantization (4-bit) to reduce size
- Optimizes the graph for CPU inference

When done, you should see a folder `onnx_model/` with several files.

### 5.4 Create Chat Template for Foundry Local

Foundry Local needs to know how to format prompts for your model.

```bash
cat > create_chat_template.py << 'ENDOFSCRIPT'
#!/usr/bin/env python3
"""
Generate inference_model.json for Foundry Local
"""

import json
import os
from transformers import AutoTokenizer

MODEL_PATH = "./merged_model"
OUTPUT_PATH = "./onnx_model"

print("Loading tokenizer...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH)

# Create a sample conversation
chat = [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "{Content}"},
]

# Generate the template
template = tokenizer.apply_chat_template(chat, tokenize=False, add_generation_prompt=True)

# Create the JSON structure
json_template = {
    "Name": "my-security-expert",  # Change this to your model name
    "PromptTemplate": {
        "assistant": "{Content}",
        "prompt": template
    }
}

# Save to file
json_file = os.path.join(OUTPUT_PATH, "inference_model.json")
with open(json_file, "w") as f:
    json.dump(json_template, f, indent=2)

print(f"✅ Chat template saved to: {json_file}")
print(f"Model name: {json_template['Name']}")
ENDOFSCRIPT

chmod +x create_chat_template.py
python create_chat_template.py
```

---

## Part 6: Import to Foundry Local

### 6.1 Verify ONNX Model Files

```bash
ls -la onnx_model/
```

You should see:
- Multiple `.onnx` files
- `genai_config.json`
- `inference_model.json` (you just created)
- Other configuration files

### 6.2 Add Model to Foundry Local Cache

The easiest way is to move your model to Foundry Local's cache directory.

First, find where Foundry Local stores models:

```bash
foundry cache list
```

This shows cached models. Note the cache location (usually in your home directory).

Now copy your model:

```bash
# Get the cache directory path
CACHE_DIR=$(foundry service status | grep -o 'cache.*' | head -1 | cut -d' ' -f1)

# Create a directory for your model
mkdir -p ~/Library/Caches/FoundryLocal/models/my-security-expert

# Copy your ONNX model
cp -r onnx_model/* ~/Library/Caches/FoundryLocal/models/my-security-expert/
```

**Alternative method** (if above doesn't work):

```bash
# Navigate to the ONNX model directory
cd ~/foundry-training/onnx_model

# Use Foundry Local CLI to add model
# This assumes your model directory has all necessary files
foundry cache
```

### 6.3 Start Foundry Local Service

```bash
foundry service start
```

### 6.4 Load Your Model

```bash
foundry model load my-security-expert
```

If you get an error, the model might need to be in the cache first. Try:

```bash
foundry cache list
```

Your model should appear in the list.

### 6.5 Test Your Model

**Interactive mode:**

```bash
foundry model run my-security-expert
```

Ask it questions similar to your training data. It should respond in the style you trained.

**Single query mode:**

```bash
curl -X POST http://localhost:5273/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "my-security-expert",
    "messages": [{"role": "user", "content": "What is Azure Firewall?"}],
    "temperature": 0.7,
    "max_tokens": 500
  }'
```

### 6.6 Use with RAG System

Now update your RAG script to use your fine-tuned model instead of phi-3.5-mini:

```bash
nano rag_assistant.py
```

Find this line:
```python
MODEL_NAME = "phi-3.5-mini"  # Change to your fine-tuned model name later
```

Change it to:
```python
MODEL_NAME = "my-security-expert"
```

Save (Ctrl+O, Enter, Ctrl+X).

Now test the complete system:

```bash
python rag_assistant.py
```

Your RAG system now uses your fine-tuned model!

---

## Part 7: Troubleshooting

### Error: "out of memory" during training

Your M2 Pro has 32GB RAM, which should be enough. If you get OOM errors:

1. Reduce batch size in `train_model.py`:
   ```python
   per_device_train_batch_size=1  # Already at minimum
   gradient_accumulation_steps=8  # Increase this instead
   ```

2. Use a smaller base model:
   ```python
   BASE_MODEL = "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
   ```

### Error: "Model not found" in Foundry Local

```bash
# List all cached models
foundry cache list

# Check service status
foundry service status

# Restart service
foundry service stop
foundry service start
```

### Training loss not decreasing

1. **Add more training examples** - You need 50-100+ quality examples
2. **Check data format**:
   ```bash
   cat training_data/train.jsonl | python -m json.tool
   ```
   If you get errors, your JSONL is malformed

3. **Increase training epochs**:
   ```python
   num_train_epochs=5  # Instead of 3
   ```

### Olive conversion fails

Common issues:

1. **"Model too large"** - Use smaller base model or more aggressive quantization
2. **"Unsupported operation"** - Some model architectures don't convert well to ONNX
3. **Missing dependencies**:
   ```bash
   pip install --upgrade onnxruntime onnxruntime-genai
   ```

### Model gives nonsense responses

1. **Test the PyTorch version first**:
   ```bash
   python test_model.py
   ```
   If PyTorch works but ONNX doesn't, the conversion had issues

2. **Check the chat template** - Make sure `inference_model.json` matches your model's expected format

3. **You may have overtrained** - Try training for fewer epochs:
   ```python
   num_train_epochs=1
   ```

### Foundry Local won't start

```bash
# Check if port is in use
lsof -i :5273

# Kill any processes using that port
kill -9 <PID>

# Restart
foundry service stop
foundry service start
```

### RAG returns poor answers

1. **Rebuild the index with more documents**:
   ```bash
   python rag_assistant.py --rebuild
   ```

2. **Adjust chunk size** in `rag_assistant.py`:
   ```python
   Settings.chunk_size = 512  # Smaller chunks
   Settings.chunk_overlap = 100
   ```

3. **Check that Foundry Local is running**:
   ```bash
   foundry service status
   ```

---

## Part 8: Quick Reference

### Daily Commands

```bash
# Start working on the project
cd ~/foundry-training
source venv/bin/activate

# Start Foundry Local (if not running)
foundry service start

# Load your model
foundry model load my-security-expert

# Run RAG assistant
python rag_assistant.py

# Rebuild RAG index after adding documents
python rag_assistant.py --rebuild

# Test your model directly
foundry model run my-security-expert
```

### Training Pipeline Commands

```bash
# 1. Prepare training data
# Edit training_data/train.jsonl and training_data/valid.jsonl

# 2. Train the model
python train_model.py

# 3. Test PyTorch version
python test_model.py

# 4. Merge LoRA adapters
python merge_model.py

# 5. Convert to ONNX
olive auto-opt \
  --model_name_or_path ./merged_model \
  --output_path ./onnx_model \
  --device cpu \
  --provider CPUExecutionProvider \
  --use_ort_genai \
  --precision int4

# 6. Create chat template
python create_chat_template.py

# 7. Copy to Foundry Local cache
cp -r onnx_model/* ~/Library/Caches/FoundryLocal/models/my-security-expert/

# 8. Load and test
foundry model load my-security-expert
foundry model run my-security-expert
```

### File Locations

```
~/foundry-training/
├── venv/                        # Python virtual environment
├── documents/                   # Your PDFs and documents for RAG
├── index_storage/               # RAG vector index (auto-generated)
├── training_data/               # Fine-tuning data
│   ├── train.jsonl
│   └── valid.jsonl
├── fine_tuned_model/            # LoRA adapters (auto-generated)
├── merged_model/                # Merged model (auto-generated)
├── onnx_model/                  # ONNX format model (auto-generated)
├── rag_assistant.py             # RAG script
├── train_model.py               # Training script
├── test_model.py                # Testing script
├── merge_model.py               # Merge script
└── create_chat_template.py      # Template generator
```

### Foundry Local Commands

```bash
# Service management
foundry service start
foundry service stop
foundry service status

# Model management
foundry model list              # List available models
foundry model load <name>       # Load a model
foundry model run <name>        # Interactive chat
foundry cache list              # Show cached models
foundry cache remove <name>     # Remove a cached model

# Get help
foundry --help
foundry model --help
```

### Useful Checks

```bash
# Check if Foundry Local is running
curl http://localhost:5273/v1/models

# Check GPU/CPU usage during training
# Open Activity Monitor (Command + Space, type "Activity Monitor")

# Check disk space (models are large!)
df -h

# Check Python packages
pip list | grep -E 'transformers|torch|olive|onnx'

# Verify training data format
python -c "import json; [json.loads(line) for line in open('training_data/train.jsonl')]"
```

---

## Summary

You now have:

1. **RAG System** - Queries your documents for accurate, cited answers
2. **Fine-Tuned Model** - Responds in your trained style/terminology
3. **ONNX Format** - Compatible with Foundry Local
4. **Local Deployment** - Everything runs on your Mac, privately

**The Complete Workflow:**

1. Add documents to `documents/` folder
2. Create training examples in `training_data/train.jsonl`
3. Run `python train_model.py` to fine-tune
4. Run conversion scripts to get ONNX model
5. Load into Foundry Local
6. Use `python rag_assistant.py` for document Q&A with your custom model

**Key Differences from Ollama:**

- Foundry Local uses ONNX (not GGUF)
- Optimized for Microsoft's ONNX Runtime
- Direct integration with Azure AI ecosystem
- Better for production/enterprise deployments

**Performance on Your M2 Pro:**

- Training: 2-4 hours for 100 examples
- Inference: 20-50 tokens/second (depending on model size)
- RAM usage: 8-16GB during inference
- Best model size: 7B parameters with 4-bit quantization

---

## Appendix: Verification Script

Save as `verify_setup.sh`:

```bash
#!/bin/bash

echo "=========================================="
echo "Foundry Local Setup Verification"
echo "=========================================="

# Check Homebrew
echo "1. Checking Homebrew..."
if command -v brew &> /dev/null; then
    echo "   ✓ Homebrew installed: $(brew --version | head -1)"
else
    echo "   ✗ Homebrew not installed"
fi

# Check Python
echo "2. Checking Python..."
if command -v python3.11 &> /dev/null; then
    echo "   ✓ Python installed: $(python3.11 --version)"
else
    echo "   ✗ Python 3.11 not installed"
fi

# Check Foundry Local
echo "3. Checking Foundry Local..."
if command -v foundry &> /dev/null; then
    echo "   ✓ Foundry Local installed: $(foundry --version | head -1)"
else
    echo "   ✗ Foundry Local not installed"
fi

# Check virtual environment
echo "4. Checking virtual environment..."
if [ -d "$HOME/foundry-training/venv" ]; then
    echo "   ✓ Virtual environment exists"
else
    echo "   ✗ Run: cd ~/foundry-training && python3.11 -m venv venv"
fi

# Check if venv is activated
echo "5. Checking if venv is activated..."
if [[ "$VIRTUAL_ENV" == *"foundry-training"* ]]; then
    echo "   ✓ Virtual environment is activated"
else
    echo "   ⚠ Run: source ~/foundry-training/venv/bin/activate"
fi

# Check documents directory
echo "6. Checking documents directory..."
if [ -d "$HOME/foundry-training/documents" ]; then
    COUNT=$(find "$HOME/foundry-training/documents" -type f 2>/dev/null | wc -l)
    echo "   ✓ Documents directory has $COUNT files"
else
    echo "   ⚠ Run: mkdir -p ~/foundry-training/documents"
fi

# Check Foundry Local service
echo "7. Checking Foundry Local service..."
if curl -s http://localhost:5273/v1/models > /dev/null 2>&1; then
    echo "   ✓ Foundry Local service is running"
else
    echo "   ⚠ Service not running. Run: foundry service start"
fi

# Check for models
echo "8. Checking cached models..."
foundry cache list 2>/dev/null | tail -n +2 | head -5

echo "=========================================="
echo "Verification complete!"
echo "=========================================="
```

Run it:

```bash
chmod +x verify_setup.sh
./verify_setup.sh
```

---

## What the Previous Guide Got Wrong

| Issue | Previous Guide (Ollama) | This Guide (Foundry Local) |
|-------|------------------------|---------------------------|
| Training Framework | MLX (Apple-specific) | PyTorch (industry standard) |
| Output Format | GGUF | ONNX |
| Conversion Tool | llama.cpp | Microsoft Olive |
| Runtime | Ollama | Foundry Local |
| Compatibility | macOS only | Cross-platform via ONNX |

Your previous guide was excellent for Ollama. This guide is specifically designed for Foundry Local's requirements.
